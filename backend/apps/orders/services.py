"""Business logic for orders (doc section 12).

Flow: customer orders (stock held) -> pays online, or chooses cash -> shop accepts -> marks ready /
out for delivery -> completes with the customer's 4-digit code (stock sold, commission recorded).
Unpaid or unanswered orders are cancelled automatically and their stock released; paid ones are refunded.
"""
import secrets
import string
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone

from apps.audit.services import record
from apps.commissions import services as commissions
from apps.deals import services as deal_services
from apps.deals.models import Deal
from apps.inventory import services as inventory
from apps.notifications import services as notifications
from common.exceptions import BusinessRuleError

from .models import Coupon, Order, OrderItem

Status = Order.Status
Kind = notifications.Kind
PAISE = Decimal("0.01")
MAX_ITEMS = 20
_ALPHABET = string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789"


def _money(value):
    return value.quantize(PAISE, rounding=ROUND_HALF_UP)


def _new_order_number():
    while True:
        number = "OD-" + "".join(secrets.choice(_ALPHABET) for _ in range(6))
        if not Order.objects.filter(order_number=number).exists():
            return number


def _lock(order):
    return Order.objects.select_for_update().select_related("shop__merchant__user", "customer").get(pk=order.pk)


# ---------- coupons ----------

def coupon_discount(coupon, customer, shop, subtotal):
    """Validate a coupon for this basket and return the discount. Caller locks the coupon row."""
    now = timezone.now()
    if not coupon.is_active or not (coupon.valid_from <= now < coupon.valid_until):
        raise BusinessRuleError("This coupon has expired.", "coupon_invalid")
    if coupon.shop_id and coupon.shop_id != shop.id:
        raise BusinessRuleError("This coupon is not valid at this shop.", "coupon_invalid")
    if coupon.customer_id and coupon.customer_id != customer.id:
        raise BusinessRuleError("Coupon not found.", "coupon_invalid")
    if coupon.first_order_only and _has_ordered(customer):
        raise BusinessRuleError("This coupon is only for your first order.", "coupon_first_order")
    if subtotal < coupon.min_order_amount:
        raise BusinessRuleError(f"Add items worth ₹{coupon.min_order_amount} to use this coupon.", "coupon_min_order")
    used = coupon.orders.exclude(status=Status.CANCELLED)
    if coupon.usage_limit is not None and used.count() >= coupon.usage_limit:
        raise BusinessRuleError("This coupon has been fully used.", "coupon_exhausted")
    if used.filter(customer=customer).count() >= coupon.per_customer_limit:
        raise BusinessRuleError("You have already used this coupon.", "coupon_already_used")
    if coupon.discount_type == Coupon.DiscountType.PERCENT:
        discount = subtotal * coupon.value / 100
        if coupon.max_discount is not None:
            discount = min(discount, coupon.max_discount)
    else:
        discount = coupon.value
    return _money(min(discount, subtotal))


def _has_ordered(customer):
    from apps.customers.services import has_purchased

    return has_purchased(customer) or customer.orders.exclude(status=Status.CANCELLED).exists()


def available_offers(customer, shop_id=None):
    """Coupons this customer can use now: platform-wide, the shop's own, and personal (e.g. referral rewards)."""
    now = timezone.now()
    coupons = (
        Coupon.objects.filter(is_active=True, valid_from__lte=now, valid_until__gt=now)
        .filter(Q(customer=None) | Q(customer=customer))
        .filter(Q(shop=None) | (Q(shop_id=shop_id) if shop_id else Q(shop__status="approved")))
        .select_related("shop")
        .annotate(
            used_total=Count("orders", filter=~Q(orders__status=Status.CANCELLED), distinct=True),
            used_by_me=Count("orders", filter=Q(orders__customer=customer) & ~Q(orders__status=Status.CANCELLED), distinct=True),
        )
        .order_by("-customer", "valid_until")
    )
    first_order = not _has_ordered(customer)
    return [
        c for c in coupons
        if (c.usage_limit is None or c.used_total < c.usage_limit)
        and c.used_by_me < c.per_customer_limit
        and (first_order or not c.first_order_only)
    ]


# ---------- customer ----------

def _check_fulfilment(deal, fulfilment):
    wanted = Deal.Fulfilment.PICKUP if fulfilment == Order.Fulfilment.PICKUP else Deal.Fulfilment.DELIVERY
    if deal.fulfilment not in (wanted, Deal.Fulfilment.BOTH):
        raise BusinessRuleError(f"{deal.product.name} is not available for {fulfilment}.", "fulfilment_unavailable")


def create_order(customer, items, fulfilment, payment_method, address=None, coupon_code="", note=""):
    """items: [{"deal": id, "quantity": Decimal}] from one shop."""
    if not items or len(items) > MAX_ITEMS:
        raise BusinessRuleError(f"An order must have 1 to {MAX_ITEMS} items.", "invalid_items")
    if len({item["deal"] for item in items}) != len(items):
        raise BusinessRuleError("Each deal can appear only once in an order.", "invalid_items")
    if payment_method == Order.PaymentMethod.CASH and not settings.ALLOW_CASH_PAYMENT:
        raise BusinessRuleError("Cash payment is not available.", "cash_unavailable")
    if fulfilment == Order.Fulfilment.DELIVERY and address is None:
        raise BusinessRuleError("Choose a delivery address.", "address_required")
    open_count = customer.orders.filter(status__in=Order.OPEN_STATUSES).count()
    if open_count >= settings.MAX_OPEN_ORDERS_PER_CUSTOMER:
        raise BusinessRuleError(
            f"You can have at most {settings.MAX_OPEN_ORDERS_PER_CUSTOMER} open orders.", "order_limit"
        )

    now = timezone.now()
    with transaction.atomic():
        # Lock deals in id order so two baskets with the same deals cannot deadlock.
        deals = {}
        for item in sorted(items, key=lambda i: i["deal"]):
            deals[item["deal"]] = deal_services.reserve_quantity(item["deal"], item["quantity"])
        shop = next(iter(deals.values())).shop
        if any(deal.shop_id != shop.id for deal in deals.values()):
            raise BusinessRuleError("All items in an order must be from the same shop.", "multiple_shops")
        if fulfilment == Order.Fulfilment.DELIVERY and not shop.offers_delivery:
            raise BusinessRuleError("This shop does not deliver.", "fulfilment_unavailable")

        lines = []
        for item in items:
            deal = deals[item["deal"]]
            _check_fulfilment(deal, fulfilment)
            lines.append(OrderItem(
                deal=deal, product_name=deal.product.name, unit=deal.unit, quantity=item["quantity"],
                unit_price=deal.offer_price, normal_unit_price=deal.normal_price,
                line_total=_money(deal.offer_price * item["quantity"]),
            ))
        subtotal = sum((line.line_total for line in lines), Decimal("0"))
        savings = sum((_money((line.normal_unit_price - line.unit_price) * line.quantity) for line in lines), Decimal("0"))

        coupon, discount = None, Decimal("0")
        if coupon_code:
            coupon = Coupon.objects.select_for_update().filter(code=coupon_code.strip().upper()).first()
            if coupon is None:
                raise BusinessRuleError("Coupon not found.", "coupon_invalid")
            discount = coupon_discount(coupon, customer, shop, subtotal)

        delivery_fee = Decimal("0")
        if fulfilment == Order.Fulfilment.DELIVERY and subtotal < settings.FREE_DELIVERY_ABOVE:
            delivery_fee = Decimal(settings.DELIVERY_FEE)
        total = subtotal - discount + delivery_fee

        online = payment_method == Order.PaymentMethod.ONLINE and total > 0
        order = Order.objects.create(
            order_number=_new_order_number(), customer=customer, shop=shop, fulfilment=fulfilment,
            status=Status.PENDING_PAYMENT if online else Status.PENDING,
            payment_method=payment_method,
            payment_status=Order.PaymentStatus.PAID if total == 0 else Order.PaymentStatus.UNPAID,
            delivery_address=_address_text(address) if fulfilment == Order.Fulfilment.DELIVERY else "",
            delivery_latitude=address.latitude if fulfilment == Order.Fulfilment.DELIVERY else None,
            delivery_longitude=address.longitude if fulfilment == Order.Fulfilment.DELIVERY else None,
            subtotal=subtotal, savings=savings, coupon=coupon, coupon_discount=discount,
            delivery_fee=delivery_fee, total_amount=total, pickup_code=f"{secrets.randbelow(10000):04d}", note=note,
            expires_at=now + timedelta(minutes=settings.ORDER_PAYMENT_MINUTES if online else settings.ORDER_ACCEPT_MINUTES),
        )
        for line in lines:
            line.order = order
        OrderItem.objects.bulk_create(lines)
        if not online:
            _tell_shop_new_order(order)
    return order


def _address_text(address):
    parts = [address.address_line, address.landmark, address.city, address.pincode]
    return ", ".join(part for part in parts if part)


def _tell_shop_new_order(order):
    how = "डिलीवरी" if order.fulfilment == Order.Fulfilment.DELIVERY else "पिकअप"
    paid = "पेमेंट हो गया" if order.payment_status == Order.PaymentStatus.PAID else "कैश"
    notifications.notify(
        order.shop.merchant.user, Kind.NEW_ORDER, f"नया ऑर्डर {order.order_number}",
        f"₹{order.total_amount} ({how}, {paid})। {settings.ORDER_ACCEPT_MINUTES} मिनट में स्वीकार करें।",
        data={"order_id": str(order.id)},
    )


def _tell_customer(order, title, body):
    notifications.notify(
        order.customer, Kind.ORDER_UPDATE, title, body, data={"order_id": str(order.id)},
        push=notifications.wants_order_updates(order.customer),
    )


@transaction.atomic
def mark_paid(order):
    """Called by the payments app when the online payment succeeds. Returns False if the order
    was already cancelled (e.g. payment came after the time limit) so the caller refunds it."""
    order = _lock(order)
    if order.status != Status.PENDING_PAYMENT:
        return order.status != Status.CANCELLED
    order.status = Status.PENDING
    order.payment_status = Order.PaymentStatus.PAID
    order.expires_at = timezone.now() + timedelta(minutes=settings.ORDER_ACCEPT_MINUTES)
    order.save(update_fields=["status", "payment_status", "expires_at", "updated_at"])
    _tell_shop_new_order(order)
    return True


@transaction.atomic
def cancel_by_customer(order, reason=""):
    order = _lock(order)
    if order.status not in (Status.PENDING_PAYMENT, Status.PENDING):
        raise BusinessRuleError("The shop has already accepted this order. Contact the shop or support.", "cannot_cancel")
    _cancel(order, reason or "Cancelled by customer.")
    notifications.notify(
        order.shop.merchant.user, Kind.ORDER_CANCELLED, f"ऑर्डर रद्द {order.order_number}",
        "ग्राहक ने ऑर्डर रद्द कर दिया। स्टॉक वापस डील में जुड़ गया।", data={"order_id": str(order.id)},
    )
    return order


def _cancel(order, reason, actor=None):
    """Release stock and refund anything paid. Caller holds the order lock."""
    for item in order.items.all():
        deal_services.release_quantity(item.deal_id, item.quantity)
    order.status = Status.CANCELLED
    order.cancel_reason = reason
    order.cancelled_at = timezone.now()
    order.expires_at = None
    order.save(update_fields=["status", "cancel_reason", "cancelled_at", "expires_at", "updated_at"])
    if order.payment_status == Order.PaymentStatus.PAID and order.payment_method == Order.PaymentMethod.ONLINE:
        from apps.payments.services import refund_order

        refund_order(order, order.total_amount, reason, actor)


# ---------- shop ----------

def _transition(order, allowed, message):
    if order.status not in allowed:
        raise BusinessRuleError(f"{message} (this order is {order.get_status_display().lower()}).", "invalid_status")


@transaction.atomic
def accept(order):
    order = _lock(order)
    _transition(order, (Status.PENDING,), "Only new orders can be accepted")
    order.status = Status.CONFIRMED
    order.confirmed_at = timezone.now()
    order.expires_at = None
    order.save(update_fields=["status", "confirmed_at", "expires_at", "updated_at"])
    _tell_customer(order, "ऑर्डर कन्फर्म ✅", f"{order.shop.name} आपका ऑर्डर {order.order_number} तैयार कर रही है।")
    return order


@transaction.atomic
def mark_ready(order):
    order = _lock(order)
    _transition(order, (Status.CONFIRMED,), "Accept the order first")
    if order.fulfilment == Order.Fulfilment.DELIVERY:
        order.status = Status.OUT_FOR_DELIVERY
        title, body = "ऑर्डर रास्ते में है 🛵", f"डिलीवरी पर कोड {order.pickup_code} बताएं।"
    else:
        order.status = Status.READY
        title, body = "ऑर्डर तैयार है 🛍️", f"{order.shop.name} से पिकअप करें। दुकान पर अपना पिकअप कोड बताएं।"
    order.ready_at = timezone.now()
    order.save(update_fields=["status", "ready_at", "updated_at"])
    _tell_customer(order, title, body)
    return order


@transaction.atomic
def complete(order, pickup_code):
    order = _lock(order)
    _transition(order, (Status.READY, Status.OUT_FOR_DELIVERY), "Mark the order ready first")
    if order.pickup_code != pickup_code:
        raise BusinessRuleError("Code does not match.", "wrong_pickup_code")
    for item in order.items.select_related("deal"):
        deal_services.complete_quantity(item.deal_id, item.quantity)
        inventory.record_sale(item.deal.product_id, item.quantity, order.order_number)
    order.status = Status.COMPLETED
    order.completed_at = timezone.now()
    order.payment_status = Order.PaymentStatus.PAID  # cash is collected at handover
    order.save(update_fields=["status", "completed_at", "payment_status", "updated_at"])
    commissions.record_for_order(order)
    from apps.customers.services import reward_referral

    reward_referral(order.customer)
    _tell_customer(order, "ऑर्डर पूरा 🎉", f"आपने इस ऑर्डर पर ₹{order.savings + order.coupon_discount} बचाए!")
    return order


@transaction.atomic
def cancel_by_shop(order, reason):
    order = _lock(order)
    _transition(order, (Status.PENDING, Status.CONFIRMED, Status.READY, Status.OUT_FOR_DELIVERY), "This order cannot be cancelled")
    _cancel(order, reason or "Cancelled by shop.")
    refund = " पेमेंट वापस किया जाएगा।" if order.payment_status == Order.PaymentStatus.PAID else ""
    _tell_customer(order, "ऑर्डर रद्द", f"{order.shop.name} ने ऑर्डर {order.order_number} रद्द किया: {order.cancel_reason}{refund}")
    return order


# ---------- admin ----------

@transaction.atomic
def refund_completed_order(order, amount, reason, actor):
    """Refund (part of) a completed order, e.g. after a complaint. A full refund also reverses the commission."""
    from apps.payments.services import refund_order

    order = _lock(order)
    if order.status != Status.COMPLETED:
        raise BusinessRuleError("Only completed orders are refunded this way; cancel open orders instead.", "invalid_status")
    if order.payment_method != Order.PaymentMethod.ONLINE:
        raise BusinessRuleError("Cash orders are refunded by the shop directly.", "cash_order")
    refund_order(order, amount, reason, actor)
    order.refresh_from_db()
    if order.refunded_amount >= order.total_amount:
        order.status = Status.REFUNDED
        order.save(update_fields=["status", "updated_at"])
        commissions.reverse_for_order(order, actor)
    record(actor, "order.refunded", order, reason, amount=amount)
    return order


# ---------- background job ----------

def expire_orders():
    """Cancel orders that were not paid, or not accepted by the shop, in time. Run every minute."""
    count = 0
    due = Order.objects.filter(status__in=(Status.PENDING_PAYMENT, Status.PENDING), expires_at__lte=timezone.now())
    for order_id in due.values_list("id", flat=True):
        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("shop", "customer").get(pk=order_id)
            if order.status not in (Status.PENDING_PAYMENT, Status.PENDING) or order.expires_at > timezone.now():
                continue  # paid, accepted or cancelled meanwhile
            if order.status == Status.PENDING_PAYMENT:
                _cancel(order, "Payment was not completed in time.")
            else:
                _cancel(order, "The shop did not respond in time.")
                refund = " आपका पेमेंट वापस किया जाएगा।" if order.payment_status == Order.PaymentStatus.PAID else ""
                _tell_customer(order, "ऑर्डर रद्द", f"{order.shop.name} ने समय पर जवाब नहीं दिया।{refund}")
            count += 1
    return count
