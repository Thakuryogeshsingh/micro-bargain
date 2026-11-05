"""Business logic for the deals app.

Every stock change locks the deal row (select_for_update) inside a transaction, and the
database check constraints on Deal reject anything that would still slip through.
"""
from datetime import timedelta

from django.conf import settings
from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.measure import D
from django.db import transaction
from django.db.models import BooleanField, ExpressionWrapper, F, Q
from django.utils import timezone

from apps.inventory import services as inventory
from apps.notifications import services as notifications
from apps.shops.models import Shop
from apps.shops.services import make_point
from apps.subscriptions.services import check_deal_limit
from common.exceptions import BusinessRuleError

from .models import Deal, DealChangeLog

Status = Deal.Status


# ---------- helpers ----------

def _lock(deal):
    return Deal.objects.select_for_update().select_related("shop").get(pk=deal.pk)


def _log(deal, user, field, old, new):
    if str(old) != str(new):
        DealChangeLog.objects.create(deal=deal, changed_by=user, field=field, old_value=str(old), new_value=str(new))


def _validate_prices(normal_price, offer_price):
    if offer_price <= 0:
        raise BusinessRuleError("Offer price must be more than ₹0.", "invalid_price")
    if offer_price >= normal_price:
        raise BusinessRuleError("Offer price must be lower than the normal price.", "invalid_price")


def _validate_window(starts_at, expires_at):
    if expires_at <= starts_at:
        raise BusinessRuleError("Expiry time must be after the start time.", "invalid_time")
    if expires_at <= timezone.now():
        raise BusinessRuleError("Expiry time must be in the future.", "invalid_time")
    if expires_at - starts_at > timedelta(hours=settings.MAX_DEAL_DURATION_HOURS):
        raise BusinessRuleError(
            f"A deal can run for at most {settings.MAX_DEAL_DURATION_HOURS} hours.", "invalid_time"
        )


def _validate_fulfilment(shop, fulfilment):
    if fulfilment in (Deal.Fulfilment.DELIVERY, Deal.Fulfilment.BOTH) and not shop.offers_delivery:
        raise BusinessRuleError("Turn on delivery for your shop before offering delivery deals.", "delivery_off")


def _ensure_editable(deal):
    if deal.status in Deal.FINAL_STATUSES:
        raise BusinessRuleError(f"This deal has {deal.status} and cannot be changed.", "deal_closed")


def _sync_sold_out(deal):
    """Flip between active and sold_out when stock runs out or comes back."""
    if deal.status == Status.ACTIVE and deal.quantity_available <= 0:
        deal.status = Status.SOLD_OUT
    elif deal.status == Status.SOLD_OUT and deal.quantity_available > 0 and deal.expires_at > timezone.now():
        deal.status = Status.ACTIVE


# ---------- merchant actions ----------

def create_deal(user, *, shop, product, offer_price, quantity_total, normal_price=None, starts_at=None,
                expires_at=None, duration_minutes=None, description="", image=None,
                fulfilment=Deal.Fulfilment.PICKUP, publish=False):
    if product.shop_id != shop.id:
        raise BusinessRuleError("This product does not belong to the selected shop.", "product_shop_mismatch")
    if not product.is_active:
        raise BusinessRuleError("This product is inactive. Activate it first.", "product_inactive")

    starts_at = starts_at or timezone.now()
    if expires_at is None:
        if not duration_minutes:
            raise BusinessRuleError("Set an expiry time or a duration.", "invalid_time")
        expires_at = starts_at + timedelta(minutes=duration_minutes)
    normal_price = normal_price or product.standard_price

    _validate_prices(normal_price, offer_price)
    _validate_window(starts_at, expires_at)
    _validate_fulfilment(shop, fulfilment)
    inventory.check_deal_quantity(product, quantity_total)

    with transaction.atomic():
        deal = Deal.objects.create(
            shop=shop, product=product, unit=product.unit, description=description, image=image or "",
            normal_price=normal_price, offer_price=offer_price, quantity_total=quantity_total,
            starts_at=starts_at, expires_at=expires_at, fulfilment=fulfilment,
        )
        if publish:
            deal = publish_deal(deal, user)
    return deal


@transaction.atomic
def publish_deal(deal, user):
    deal = _lock(deal)
    if deal.status not in (Status.DRAFT, Status.PAUSED):
        raise BusinessRuleError(f"Only draft or paused deals can be published (this one is {deal.status}).", "invalid_status")
    if not deal.shop.is_live:
        raise BusinessRuleError("Your shop must be approved and open before publishing deals.", "shop_not_live")
    if deal.expires_at <= timezone.now():
        raise BusinessRuleError("This deal's time is already over. Change the expiry time first.", "deal_expired")
    if deal.quantity_available <= 0:
        raise BusinessRuleError("Add stock before publishing.", "no_stock")
    check_deal_limit(deal.shop)

    _log(deal, user, "status", deal.status, Status.ACTIVE)
    first_publish = deal.published_at is None
    deal.status = Status.ACTIVE
    deal.published_at = deal.published_at or timezone.now()
    deal.save(update_fields=["status", "published_at", "updated_at"])
    if first_publish:  # resuming a paused deal does not alert customers again
        notifications.schedule_new_deal_alerts(deal)
    return deal


@transaction.atomic
def change_status(deal, user, new_status):
    """pause / sold_out / end."""
    allowed_from = {
        Status.PAUSED: (Status.ACTIVE,),
        Status.SOLD_OUT: (Status.ACTIVE, Status.PAUSED),
        Status.ENDED: (Status.DRAFT, Status.ACTIVE, Status.PAUSED, Status.SOLD_OUT),
    }[new_status]
    deal = _lock(deal)
    if deal.status not in allowed_from:
        raise BusinessRuleError(f"Cannot change a {deal.status} deal to {new_status}.", "invalid_status")
    _log(deal, user, "status", deal.status, new_status)
    deal.status = new_status
    deal.save(update_fields=["status", "updated_at"])
    return deal


EDITABLE_FIELDS = ("normal_price", "offer_price", "expires_at", "description", "fulfilment", "image")


@transaction.atomic
def update_deal(deal, user, **changes):
    deal = _lock(deal)
    _ensure_editable(deal)
    normal = changes.get("normal_price", deal.normal_price)
    offer = changes.get("offer_price", deal.offer_price)
    _validate_prices(normal, offer)
    if "expires_at" in changes:
        _validate_window(deal.starts_at, changes["expires_at"])
    if "fulfilment" in changes:
        _validate_fulfilment(deal.shop, changes["fulfilment"])

    for field in EDITABLE_FIELDS:
        if field in changes:
            if field != "image":
                _log(deal, user, field, getattr(deal, field), changes[field])
            setattr(deal, field, changes[field])
    deal.save()
    return deal


@transaction.atomic
def update_stock(deal, user, quantity_total):
    deal = _lock(deal)
    _ensure_editable(deal)
    committed = deal.quantity_reserved + deal.quantity_sold
    if quantity_total < committed:
        raise BusinessRuleError(
            f"Stock cannot be less than what is already reserved or sold ({committed} {deal.unit}).", "stock_below_committed"
        )
    if quantity_total > deal.quantity_total:
        inventory.check_deal_quantity(deal.product, quantity_total - deal.quantity_sold)
    _log(deal, user, "quantity_total", deal.quantity_total, quantity_total)
    deal.quantity_total = quantity_total
    _sync_sold_out(deal)
    deal.save(update_fields=["quantity_total", "status", "updated_at"])
    return deal


def duplicate_deal(deal, user):
    """Copy a previous deal as a new draft starting now, with the same duration."""
    duration = deal.expires_at - deal.starts_at
    starts_at = timezone.now()
    return create_deal(
        user, shop=deal.shop, product=deal.product, normal_price=deal.normal_price, offer_price=deal.offer_price,
        quantity_total=deal.quantity_total, starts_at=starts_at, expires_at=starts_at + duration,
        description=deal.description, fulfilment=deal.fulfilment,
    )


# ---------- stock movements used by reservations / orders ----------
# Callers must already be inside transaction.atomic().

def reserve_quantity(deal_id, quantity):
    deal = Deal.objects.select_for_update().select_related("shop").get(pk=deal_id)
    if not deal.is_live:
        raise BusinessRuleError("This deal is no longer available.", "deal_unavailable")
    if quantity <= 0:
        raise BusinessRuleError("Quantity must be more than zero.", "invalid_quantity")
    if quantity > deal.quantity_available:
        raise BusinessRuleError(
            f"Only {deal.quantity_available} {deal.unit} left.", "insufficient_stock"
        )
    deal.quantity_reserved = F("quantity_reserved") + quantity
    deal.save(update_fields=["quantity_reserved", "updated_at"])
    deal.refresh_from_db()
    _sync_sold_out(deal)
    deal.save(update_fields=["status", "updated_at"])
    return deal


def release_quantity(deal_id, quantity):
    """A reservation was cancelled, rejected or expired: give the stock back."""
    deal = Deal.objects.select_for_update().get(pk=deal_id)
    deal.quantity_reserved = F("quantity_reserved") - quantity
    deal.save(update_fields=["quantity_reserved", "updated_at"])
    deal.refresh_from_db()
    _sync_sold_out(deal)
    deal.save(update_fields=["status", "updated_at"])
    return deal


def complete_quantity(deal_id, quantity):
    """A reservation was picked up: reserved stock becomes sold."""
    deal = Deal.objects.select_for_update().get(pk=deal_id)
    deal.quantity_reserved = F("quantity_reserved") - quantity
    deal.quantity_sold = F("quantity_sold") + quantity
    deal.save(update_fields=["quantity_reserved", "quantity_sold", "updated_at"])
    deal.refresh_from_db()
    return deal


# ---------- background jobs ----------

def expire_deals():
    """Close every open deal whose time is over. Run every minute by Celery Beat."""
    open_statuses = (Status.DRAFT, Status.ACTIVE, Status.PAUSED, Status.SOLD_OUT)
    return Deal.objects.filter(status__in=open_statuses, expires_at__lte=timezone.now()).update(
        status=Status.EXPIRED, updated_at=timezone.now()
    )


# ---------- discovery ----------

SORTS = {
    "distance": ("-is_featured", "distance", "-discount_percent"),  # promoted deals first
    "price": ("offer_price", "distance"),
    "discount": ("-discount_percent", "distance"),
    "ending_soon": ("expires_at", "distance"),
    "newest": ("-published_at",),
}


def live_deals():
    """Deals a customer can act on right now."""
    now = timezone.now()
    return (
        Deal.objects.filter(
            status=Status.ACTIVE,
            starts_at__lte=now,
            expires_at__gt=now,
            shop__status=Shop.Status.APPROVED,
            shop__is_temporarily_closed=False,
        )
        .alias(available=F("quantity_total") - F("quantity_reserved") - F("quantity_sold"))
        .filter(available__gt=0)
        .select_related("shop", "product", "product__category")
        .prefetch_related("product__images")
    )


def nearby_deals(latitude, longitude, radius, category=None, min_price=None, max_price=None,
                 min_discount=None, min_rating=None, q=None, fulfilment=None, sort="distance"):
    """Radius filter and distance sort run inside PostGIS (ST_DWithin + ST_Distance on a GiST index)."""
    point = make_point(latitude, longitude)
    from apps.advertisements.services import featured_deal_filter

    qs = live_deals().filter(shop__location__dwithin=(point, D(m=radius))).annotate(
        distance=Distance("shop__location", point),
        is_featured=ExpressionWrapper(featured_deal_filter(), output_field=BooleanField()),
    )
    if category:
        qs = qs.filter(product__category_id=category)
    if min_price is not None:
        qs = qs.filter(offer_price__gte=min_price)
    if max_price is not None:
        qs = qs.filter(offer_price__lte=max_price)
    if min_discount is not None:
        qs = qs.filter(discount_percent__gte=min_discount)
    if min_rating is not None:
        qs = qs.filter(shop__rating_avg__gte=min_rating)
    if q:
        qs = qs.filter(Q(product__name__icontains=q) | Q(description__icontains=q) | Q(shop__name__icontains=q))
    if fulfilment:
        qs = qs.filter(fulfilment__in=(fulfilment, Deal.Fulfilment.BOTH))
    return qs.order_by(*SORTS[sort])


# ---------- happy hour ----------

def _in_happy_hour(shop, now_local):
    if not (shop.happy_hour_enabled and shop.closing_time):
        return False
    closing = now_local.replace(hour=shop.closing_time.hour, minute=shop.closing_time.minute, second=0, microsecond=0)
    return closing - timedelta(minutes=shop.happy_hour_minutes) <= now_local < closing


def run_happy_hours():
    """Every few minutes: apply the extra discount to live deals of shops in their happy hour, and restore
    prices when it ends. Returns (applied, restored)."""
    from decimal import ROUND_DOWN, Decimal

    from apps.notifications import services as notifications

    now_local = timezone.localtime()
    applied = restored = 0
    shops = Shop.objects.filter(status=Shop.Status.APPROVED, closing_time__isnull=False)
    for shop in shops.filter(Q(happy_hour_enabled=True) | Q(deals__happy_hour_original_price__isnull=False)).distinct():
        active = _in_happy_hour(shop, now_local)
        with transaction.atomic():
            if active:
                deals = Deal.objects.select_for_update().filter(
                    shop=shop, status=Status.ACTIVE, happy_hour_original_price__isnull=True, expires_at__gt=timezone.now()
                )
                changed = 0
                for deal in deals:
                    factor = Decimal(100 - shop.happy_hour_percent) / 100
                    new_price = (deal.offer_price * factor).quantize(Decimal("1"), rounding=ROUND_DOWN)
                    if new_price < 1 or new_price >= deal.offer_price:
                        continue
                    deal.happy_hour_original_price = deal.offer_price
                    deal.offer_price = new_price
                    deal.save(update_fields=["offer_price", "happy_hour_original_price", "updated_at"])
                    changed += 1
                applied += changed
                if changed:
                    for fav in shop.favorited_by.select_related("user"):
                        notifications.notify(
                            fav.user, notifications.Kind.HAPPY_HOUR, f"🌙 {shop.name} पर हैप्पी आवर!",
                            f"अगले {shop.happy_hour_minutes} मिनट सभी डील पर {shop.happy_hour_percent}% और छूट।",
                            data={"shop_id": str(shop.id)},
                        )
            else:
                for deal in Deal.objects.select_for_update().filter(shop=shop, happy_hour_original_price__isnull=False):
                    deal.offer_price = deal.happy_hour_original_price
                    deal.happy_hour_original_price = None
                    deal.save(update_fields=["offer_price", "happy_hour_original_price", "updated_at"])
                    restored += 1
    return applied, restored


# ---------- frequently bought together ----------

def bought_together(deal, limit=6):
    """Other live deals at the same shop, ranked by how often their products were bought by the same customers."""
    from django.db.models import Count

    from apps.orders.models import OrderItem
    from apps.reservations.models import DealReservation

    buyers = set(
        DealReservation.objects.filter(deal__product=deal.product, status="completed").values_list("customer_id", flat=True)
    ) | set(OrderItem.objects.filter(deal__product=deal.product, order__status="completed").values_list("order__customer_id", flat=True))
    candidates = live_deals().filter(shop=deal.shop).exclude(pk=deal.pk)
    if buyers:
        candidates = candidates.annotate(
            together=Count("product__deals__reservations", filter=Q(product__deals__reservations__customer_id__in=buyers), distinct=True)
        ).order_by("-together", "-discount_percent")
    else:
        candidates = candidates.order_by("-discount_percent")
    return list(candidates[:limit])


# ---------- merchant helpers ----------

def repeat_yesterday(user):
    """Re-publish yesterday's deals of this merchant as fresh deals starting now (same price, stock and duration).
    Returns (created, skipped): a deal is skipped when its product is inactive or a rule (plan limit, stock) blocks it."""
    yesterday = timezone.localdate() - timedelta(days=1)
    previous = Deal.objects.filter(
        shop__merchant__user=user, published_at__date=yesterday
    ).select_related("shop", "product").order_by("published_at")
    created, skipped, seen = [], 0, set()
    for deal in previous:
        if deal.product_id in seen or Deal.objects.filter(product=deal.product, status=Status.ACTIVE).exists():
            skipped += 1
            continue
        seen.add(deal.product_id)
        try:
            copy = duplicate_deal(deal, user)
            created.append(publish_deal(copy, user))
        except BusinessRuleError:
            skipped += 1
    return created, skipped


def price_suggestion(product):
    """Suggest an offer price from this product's past deals: the smallest discount that usually sold out."""
    from decimal import ROUND_HALF_UP, Decimal

    past = Deal.objects.filter(product=product, published_at__isnull=False, status__in=FINAL_OR_SOLD)
    sold_well = [d for d in past if d.quantity_total and d.quantity_sold / d.quantity_total >= Decimal("0.7")]
    if sold_well:
        discount = min(d.discount_percent for d in sold_well)
        reason = "past"
    else:
        category = Deal.objects.filter(product__category=product.category, published_at__isnull=False, quantity_sold__gt=0)
        values = [d.discount_percent for d in category[:50]]
        discount = sum(values) / len(values) if values else Decimal("30")
        reason = "category" if values else "default"
    discount = max(Decimal("10"), min(Decimal("70"), Decimal(discount))).quantize(Decimal("1"))
    price = (product.standard_price * (100 - discount) / 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return {"normal_price": product.standard_price, "offer_price": price, "discount_percent": discount,
            "reason": reason, "based_on": len(sold_well)}


FINAL_OR_SOLD = (Status.EXPIRED, Status.ENDED, Status.SOLD_OUT)
