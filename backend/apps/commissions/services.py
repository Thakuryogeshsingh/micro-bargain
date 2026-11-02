"""Business logic for platform commissions (doc section 12.4).

Example: order ₹500 at 3% -> commission ₹15. Commission is only charged on completed transactions,
and reversed when the transaction is refunded.
"""
from decimal import ROUND_HALF_UP, Decimal

from django.conf import settings
from django.db.models import DecimalField, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone

from apps.audit.services import record

from .models import Commission, CommissionRule

Status = Commission.Status
PAISE = Decimal("0.01")


def rate_for(category_id):
    rules = {rule.category_id: rule.rate_percent for rule in CommissionRule.objects.filter(is_active=True)}
    return rules.get(category_id, rules.get(None, Decimal(settings.DEFAULT_COMMISSION_PERCENT)))


def _amount(lines):
    """lines: [(category_id, line_total)] -> commission for all lines, rounded to paise."""
    total = sum((line_total * rate_for(category_id) / 100 for category_id, line_total in lines), Decimal("0"))
    return total.quantize(PAISE, rounding=ROUND_HALF_UP)


def record_for_order(order):
    items = order.items.select_related("deal__product")
    lines = [(item.deal.product.category_id, item.line_total) for item in items]
    return Commission.objects.create(
        shop=order.shop, order=order, transaction_amount=order.subtotal, amount=_amount(lines)
    )


def record_for_reservation(reservation):
    lines = [(reservation.deal.product.category_id, reservation.total_amount)]
    return Commission.objects.create(
        shop=reservation.shop, reservation=reservation, transaction_amount=reservation.total_amount, amount=_amount(lines)
    )


def reverse_for_order(order, actor=None):
    commission = Commission.objects.filter(order=order).exclude(status=Status.REVERSED).first()
    if commission is None:
        return None
    commission.status = Status.REVERSED
    commission.save(update_fields=["status", "updated_at"])
    record(actor, "commission.reversed", commission, f"Refund of order {order.order_number}")
    return commission


def settle(commissions, actor, reference):
    """Mark commissions as collected from the merchant (e.g. deducted from a payout or paid by UPI)."""
    count = commissions.filter(status=Status.PENDING).update(
        status=Status.SETTLED, settled_at=timezone.now(), settlement_reference=reference
    )
    record(actor, "commission.settled", None, f"{count} commission(s), ref {reference}")
    return count


def summary(shop_ids):
    money = DecimalField(max_digits=12, decimal_places=2)
    qs = Commission.objects.filter(shop_id__in=shop_ids)
    result = {}
    for status in Status.values:
        result[status] = qs.filter(status=status).aggregate(total=Coalesce(Sum("amount"), Decimal(0), output_field=money))["total"]
    return result
