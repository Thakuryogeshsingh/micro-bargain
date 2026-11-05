"""Business logic for the shops app."""
from django.conf import settings
from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from django.db.models import Count, F, Max, Q
from django.utils import timezone

from apps.audit.services import record
from apps.merchants.models import MerchantProfile
from common.exceptions import BusinessRuleError

from .models import Shop


def make_point(latitude, longitude):
    # GEOS points are (x=longitude, y=latitude).
    return Point(float(longitude), float(latitude), srid=4326)


def create_shop(merchant, **data):
    if merchant.status in (MerchantProfile.Status.REJECTED, MerchantProfile.Status.SUSPENDED):
        raise BusinessRuleError("Your merchant account cannot add shops. Contact support.", "merchant_blocked")
    if merchant.shops.count() >= settings.MAX_SHOPS_PER_MERCHANT:
        raise BusinessRuleError(
            f"You can register up to {settings.MAX_SHOPS_PER_MERCHANT} shop(s).", "shop_limit"
        )
    latitude, longitude = data.pop("latitude"), data.pop("longitude")
    return Shop.objects.create(merchant=merchant, location=make_point(latitude, longitude), **data)


def update_shop(shop, **data):
    latitude, longitude = data.pop("latitude", None), data.pop("longitude", None)
    if latitude is not None and longitude is not None:
        shop.location = make_point(latitude, longitude)
    for field, value in data.items():
        setattr(shop, field, value)
    shop.save()
    return shop


def review_shop(shop, reviewer, approve, reason=""):
    """Approving a shop also approves its merchant if the merchant is still pending."""
    from apps.merchants.services import review_merchant
    from apps.notifications import services as notifications

    shop.status = Shop.Status.APPROVED if approve else Shop.Status.REJECTED
    shop.rejection_reason = "" if approve else reason
    shop.reviewed_at = timezone.now()
    shop.save(update_fields=["status", "rejection_reason", "reviewed_at", "updated_at"])
    record(reviewer, f"shop.{shop.status}", shop, reason)
    if approve and shop.merchant.status == MerchantProfile.Status.PENDING:
        review_merchant(shop.merchant, reviewer, approve=True)
    notifications.shop_reviewed(shop)
    return shop


def with_deal_stats(qs):
    """Adds live_deals_count and max_discount (over deals a customer can buy right now)."""
    now = timezone.now()
    live = (
        Q(deals__status="active", deals__starts_at__lte=now, deals__expires_at__gt=now)
        & Q(deals__quantity_total__gt=F("deals__quantity_reserved") + F("deals__quantity_sold"))
    )
    return qs.annotate(live_deals_count=Count("deals", filter=live, distinct=True), max_discount=Max("deals__discount_percent", filter=live))


def nearby_shops(latitude, longitude, radius_m, category=None):
    """Live shops within radius_m metres, nearest first. Filtering and sorting run in PostGIS."""
    point = make_point(latitude, longitude)
    qs = (
        Shop.objects.filter(
            status=Shop.Status.APPROVED,
            is_temporarily_closed=False,
            location__dwithin=(point, D(m=radius_m)),
        )
        .select_related("category")
        .annotate(distance=Distance("location", point))
    )
    # Shops with something to buy right now come first, nearest first within each group.
    qs = with_deal_stats(qs).order_by(F("live_deals_count").desc(nulls_last=True), "distance")
    if category:
        qs = qs.filter(category_id=category)
    return qs
