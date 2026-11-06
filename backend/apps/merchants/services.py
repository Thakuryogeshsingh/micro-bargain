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
    stats["onboarding_submitted"] = profile.onboarding_submitted_at is not None
    from apps.quality.models import QualityComplaint

    stats["open_complaints"] = QualityComplaint.objects.filter(shop__merchant=profile, status="open").count()
    stats["quality_score"] = shops[0].quality_score if shops else 100
    return stats


def review_merchant(profile, reviewer, approve, reason="", notify=True):
    profile.status = MerchantProfile.Status.APPROVED if approve else MerchantProfile.Status.REJECTED
    profile.rejection_reason = "" if approve else reason
    profile.reviewed_at = timezone.now()
    profile.reviewed_by = reviewer
    profile.save(update_fields=["status", "rejection_reason", "reviewed_at", "reviewed_by", "updated_at"])
    record(reviewer, f"merchant.{profile.status}", profile, reason)
    if notify:
        from apps.notifications import services as notifications

        if approve:
            notifications.notify(profile.user, notifications.Kind.MERCHANT_APPROVED, "प्रोफ़ाइल अप्रूव हो गई 🎉",
                                 "बधाई! आपका दुकानदार अकाउंट अप्रूव हो गया। अब डील डालें और बेचना शुरू करें।")
        else:
            notifications.notify(profile.user, notifications.Kind.SHOP_REJECTED, "प्रोफ़ाइल अप्रूव नहीं हुई",
                                 reason or "विवरण ठीक करके दोबारा जमा करें।")
    return profile


REQUIRED_DOCUMENTS = ("shop_photo", "id_proof")


def onboarding_status(profile):
    """The steps a new shop owner completes before the team reviews the shop."""
    shop = profile.shops.first()
    documents = list(shop.documents.values("id", "doc_type", "status", "remarks")) if shop else []
    uploaded = {d["doc_type"] for d in documents}
    steps = [
        {"key": "owner", "done": bool(profile.owner_name)},
        {"key": "shop", "done": shop is not None},
        {"key": "documents", "done": set(REQUIRED_DOCUMENTS) <= uploaded},
        {"key": "payout", "done": bool(profile.upi_id or (profile.bank_account_number and profile.bank_ifsc))},
    ]
    return {
        "steps": steps,
        "complete": all(step["done"] for step in steps),
        "required_documents": list(REQUIRED_DOCUMENTS),
        "documents": documents,
        "submitted_at": profile.onboarding_submitted_at,
        "merchant_status": profile.status,
        "shop_id": shop.id if shop else None,
        "shop_status": shop.status if shop else None,
        "rejection_reason": (shop.rejection_reason if shop else "") or profile.rejection_reason,
    }


@transaction.atomic
def submit_onboarding(profile):
    status = onboarding_status(profile)
    if not status["complete"]:
        missing = ", ".join(step["key"] for step in status["steps"] if not step["done"])
        raise BusinessRuleError(f"Complete these steps first: {missing}.", "onboarding_incomplete")
    shop = profile.shops.first()
    if shop.status == shop.Status.REJECTED:  # fixed and sent again
        shop.status = shop.Status.PENDING
        shop.rejection_reason = ""
        shop.save(update_fields=["status", "rejection_reason", "updated_at"])
    if profile.status == MerchantProfile.Status.REJECTED:
        profile.status = MerchantProfile.Status.PENDING
        profile.rejection_reason = ""
    profile.onboarding_submitted_at = timezone.now()
    profile.save(update_fields=["status", "rejection_reason", "onboarding_submitted_at", "updated_at"])
    record(profile.user, "merchant.onboarding_submitted", profile)
    return onboarding_status(profile)


def sales_report(user, days=7):
    """Completed sales per day (orders + pickups), totals and top products for the last `days` days."""
    from datetime import timedelta
    from decimal import Decimal

    from django.db.models.functions import TruncDate

    from apps.orders.models import Order, OrderItem
    from apps.reservations.models import DealReservation

    today = timezone.localdate()
    start = today - timedelta(days=days - 1)
    per_day = {start + timedelta(days=i): {"sales": Decimal(0), "count": 0} for i in range(days)}
    orders = Order.objects.filter(shop__merchant__user=user, status="completed", completed_at__date__gte=start)
    pickups = DealReservation.objects.filter(shop__merchant__user=user, status="completed", completed_at__date__gte=start)
    for qs, field in ((orders, "total_amount"), (pickups, "total_amount")):
        for row in qs.annotate(day=TruncDate("completed_at")).values("day").annotate(s=Sum(field), n=Count("id")):
            if row["day"] in per_day:
                per_day[row["day"]]["sales"] += row["s"] or 0
                per_day[row["day"]]["count"] += row["n"]
    products = {}
    for row in OrderItem.objects.filter(order__in=orders).values("product_name").annotate(q=Sum("quantity"), s=Sum("line_total")):
        products[row["product_name"]] = [row["q"], row["s"]]
    for row in pickups.values("deal__product__name").annotate(q=Sum("quantity"), s=Sum("total_amount")):
        p = products.setdefault(row["deal__product__name"], [Decimal(0), Decimal(0)])
        p[0] += row["q"]
        p[1] += row["s"]
    top = sorted(products.items(), key=lambda kv: kv[1][1], reverse=True)[:5]
    total = sum((v["sales"] for v in per_day.values()), Decimal(0))
    count = sum(v["count"] for v in per_day.values())
    return {
        "days": days,
        "total": total,
        "count": count,
        "average": (total / count).quantize(Decimal("0.01")) if count else Decimal(0),
        "series": [{"date": d, "sales": v["sales"], "count": v["count"]} for d, v in sorted(per_day.items())],
        "top_products": [{"name": n, "quantity": q, "sales": s} for n, (q, s) in top],
    }
