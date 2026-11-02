"""Business logic for merchant subscriptions.

Buying a plan creates a pending subscription; the payments app activates it when the payment succeeds.
"""
from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from common.exceptions import BusinessRuleError

from .models import MerchantSubscription, Plan

Status = MerchantSubscription.Status
DAYS_PER_MONTH = 30


def active_subscription(merchant):
    now = timezone.now()
    return (
        merchant.subscriptions.filter(status=Status.ACTIVE, starts_at__lte=now, ends_at__gt=now)
        .select_related("plan")
        .order_by("-ends_at")
        .first()
    )


def current_plan(merchant):
    subscription = active_subscription(merchant)
    return subscription.plan if subscription else Plan.objects.get(code=Plan.FREE)


def check_deal_limit(shop):
    """Called before a deal goes live."""
    from apps.deals.models import Deal

    plan = current_plan(shop.merchant)
    if plan.max_active_deals is None:
        return
    live = Deal.objects.filter(shop__merchant=shop.merchant, status=Deal.Status.ACTIVE).count()
    if live >= plan.max_active_deals:
        raise BusinessRuleError(
            f"Your {plan.name} plan allows {plan.max_active_deals} live deals at a time. "
            "End a deal or upgrade your plan.",
            "plan_deal_limit",
        )


def subscribe(merchant, plan_code, months=1):
    plan = Plan.objects.filter(code=plan_code, is_active=True).first()
    if plan is None:
        raise BusinessRuleError("This plan is not available.", "invalid_plan")
    if plan.price_monthly <= 0:
        raise BusinessRuleError("The free plan needs no purchase.", "invalid_plan")
    # An unpaid earlier attempt is replaced rather than left lying around.
    merchant.subscriptions.filter(status=Status.PENDING_PAYMENT).update(status=Status.CANCELLED)
    return MerchantSubscription.objects.create(
        merchant=merchant, plan=plan, months=months, amount=plan.price_monthly * months
    )


@transaction.atomic
def activate(subscription):
    """Payment received. Renewing the same plan starts when the current period ends, so paid days are
    never lost; a different plan (upgrade/downgrade) starts now."""
    subscription = MerchantSubscription.objects.select_for_update().get(pk=subscription.pk)
    if subscription.status == Status.ACTIVE:
        return subscription
    now = timezone.now()
    latest_end = (
        subscription.merchant.subscriptions.filter(status=Status.ACTIVE, plan=subscription.plan, ends_at__gt=now)
        .order_by("-ends_at")
        .values_list("ends_at", flat=True)
        .first()
    )
    subscription.starts_at = latest_end or now
    subscription.ends_at = subscription.starts_at + timedelta(days=DAYS_PER_MONTH * subscription.months)
    subscription.status = Status.ACTIVE
    subscription.save(update_fields=["status", "starts_at", "ends_at", "updated_at"])

    from apps.notifications import services as notifications

    notifications.notify(
        subscription.merchant.user, notifications.Kind.SUBSCRIPTION_ACTIVE, f"{subscription.plan.name} प्लान चालू ✅",
        f"आपका प्लान {timezone.localtime(subscription.ends_at):%d %b %Y} तक चलेगा।",
        data={"subscription_id": str(subscription.id)},
    )
    return subscription


def expire_subscriptions():
    return MerchantSubscription.objects.filter(status=Status.ACTIVE, ends_at__lte=timezone.now()).update(
        status=Status.EXPIRED, updated_at=timezone.now()
    )
