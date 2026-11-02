"""Business logic for the merchants app."""
from django.db import transaction
from django.db.models import Count, DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone

from apps.accounts.models import User
from apps.audit.services import record
from common.exceptions import BusinessRuleError

from .models import MerchantProfile


@transaction.atomic
def register_merchant(user, owner_name, business_category):
    """Turn a logged-in account into a merchant account (pending verification).

    One phone number = one role in the MVP, so a customer account becomes a merchant account.
    """
    if user.role == User.Role.ADMIN:
        raise BusinessRuleError("Admin accounts cannot register as merchants.", "invalid_role")
    if MerchantProfile.objects.filter(user=user).exists():
        raise BusinessRuleError("This number is already registered as a merchant.", "already_merchant")

    user.role = User.Role.MERCHANT
    if not user.name:
        user.name = owner_name
    user.save(update_fields=["role", "name"])
    return MerchantProfile.objects.create(user=user, owner_name=owner_name, business_category=business_category)


def dashboard_stats(user):
    """Numbers for the merchant home screen (doc section 6.6)."""
    from apps.deals.models import Deal
    from apps.reservations.models import DealReservation

    Status = Deal.Status
    money = DecimalField(max_digits=12, decimal_places=2)
    stats = Deal.objects.filter(shop__merchant__user=user).aggregate(
        total_deals=Count("id"),
        active_deals=Count("id", filter=Q(status=Status.ACTIVE)),
        expired_deals=Count("id", filter=Q(status=Status.EXPIRED)),
        sold_out_deals=Count("id", filter=Q(status=Status.SOLD_OUT)),
        remaining_stock=Coalesce(
            Sum(F("quantity_total") - F("quantity_reserved") - F("quantity_sold"),
                filter=Q(status__in=[Status.ACTIVE, Status.PAUSED]), output_field=money), 0, output_field=money),
        revenue=Coalesce(Sum(F("quantity_sold") * F("offer_price"), output_field=money), 0, output_field=money),
    )
    R = DealReservation.Status
    stats.update(DealReservation.objects.filter(shop__merchant__user=user).aggregate(
        total_reservations=Count("id"),
        pending_reservations=Count("id", filter=Q(status=R.PENDING)),
        completed_orders=Count("id", filter=Q(status=R.COMPLETED)),
    ))
    from apps.orders.models import Order

    stats["pending_orders"] = Order.objects.filter(shop__merchant__user=user, status=Order.Status.PENDING).count()
    stats["open_orders"] = Order.objects.filter(
        shop__merchant__user=user, status__in=[Order.Status.CONFIRMED, Order.Status.READY, Order.Status.OUT_FOR_DELIVERY]
    ).count()
    profile = user.merchant_profile
    shops = list(profile.shops.all())
    stats["rating_avg"] = max((s.rating_avg for s in shops), default=0)
    stats["merchant_status"] = profile.status
    # The app uses these to guide a new merchant: create shop -> wait for approval -> add deals.
    stats["shop_id"] = shops[0].id if shops else None
    stats["shop_status"] = shops[0].status if shops else None
    stats["shop_rejection_reason"] = shops[0].rejection_reason if shops else ""
    return stats


def review_merchant(profile, reviewer, approve, reason=""):
    profile.status = MerchantProfile.Status.APPROVED if approve else MerchantProfile.Status.REJECTED
    profile.rejection_reason = "" if approve else reason
    profile.reviewed_at = timezone.now()
    profile.reviewed_by = reviewer
    profile.save(update_fields=["status", "rejection_reason", "reviewed_at", "reviewed_by", "updated_at"])
    record(reviewer, f"merchant.{profile.status}", profile, reason)
    return profile
