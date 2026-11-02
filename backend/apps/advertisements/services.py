"""Business logic for paid promotions. Created unpaid; the payments app activates them."""
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Exists, F, OuterRef, Q
from django.utils import timezone

from apps.audit.services import record
from apps.notifications import services as notifications
from apps.shops.services import make_point
from common.exceptions import BusinessRuleError

from .models import Advertisement

Status = Advertisement.Status
Placement = Advertisement.Placement


def create_ad(user, placement, days, deal=None, title="", banner_image=None, radius_m=5000):
    shop = user.merchant_profile.shops.first()
    if shop is None or not shop.is_live:
        raise BusinessRuleError("Your shop must be approved and open to run promotions.", "shop_not_live")
    if not 1 <= days <= settings.MAX_AD_DAYS:
        raise BusinessRuleError(f"A promotion can run for 1 to {settings.MAX_AD_DAYS} days.", "invalid_days")
    if placement == Placement.FEATURED_DEAL:
        if deal is None or deal.shop_id != shop.id:
            raise BusinessRuleError("Choose one of your deals to feature.", "invalid_deal")
        if deal.status in deal.FINAL_STATUSES:
            raise BusinessRuleError("This deal has already ended.", "deal_closed")
    elif not banner_image or not title:
        raise BusinessRuleError("A banner needs a title and an image.", "banner_incomplete")
    return Advertisement.objects.create(
        shop=shop, deal=deal if placement == Placement.FEATURED_DEAL else None, placement=placement,
        title=title, banner_image=banner_image or "", radius_m=radius_m, days=days,
        price=Decimal(settings.AD_PRICE_PER_DAY[placement]) * days,
    )


@transaction.atomic
def activate(ad):
    ad = Advertisement.objects.select_for_update().get(pk=ad.pk)
    if ad.status != Status.PENDING_PAYMENT:
        return ad
    ad.status = Status.ACTIVE
    ad.starts_at = timezone.now()
    ad.ends_at = ad.starts_at + timedelta(days=ad.days)
    ad.save(update_fields=["status", "starts_at", "ends_at", "updated_at"])
    notifications.notify(
        ad.shop.merchant.user, notifications.Kind.AD_ACTIVE, "प्रमोशन चालू 📣",
        f"{ad.get_placement_display()} {timezone.localtime(ad.ends_at):%d %b} तक चलेगा।", data={"ad_id": str(ad.id)},
    )
    return ad


@transaction.atomic
def reject(ad, actor, reason):
    """Admin takes down an ad (e.g. misleading banner). A running paid ad is refunded in full."""
    from apps.payments.models import Payment
    from apps.payments.services import refund_payment

    ad = Advertisement.objects.select_for_update().get(pk=ad.pk)
    if ad.status not in (Status.PENDING_PAYMENT, Status.ACTIVE):
        raise BusinessRuleError(f"This promotion is already {ad.status}.", "invalid_status")
    payment = ad.payments.filter(status=Payment.Status.PAID).first()
    if payment:
        refund_payment(payment, payment.amount, f"Promotion rejected: {reason}", actor)
    ad.status = Status.REJECTED
    ad.rejection_reason = reason
    ad.save(update_fields=["status", "rejection_reason", "updated_at"])
    record(actor, "advertisement.rejected", ad, reason)
    return ad


def running(placement):
    now = timezone.now()
    return Advertisement.objects.filter(placement=placement, status=Status.ACTIVE, starts_at__lte=now, ends_at__gt=now)


def featured_deal_filter():
    """Exists() expression for Deal querysets: True when the deal is promoted or its merchant's plan includes featuring."""
    from apps.subscriptions.models import MerchantSubscription

    now = timezone.now()
    paid_ad = running(Placement.FEATURED_DEAL).filter(deal=OuterRef("pk"))
    plan = MerchantSubscription.objects.filter(
        merchant=OuterRef("shop__merchant"), status=MerchantSubscription.Status.ACTIVE,
        starts_at__lte=now, ends_at__gt=now, plan__featured_listing=True,
    )
    return Q(Exists(paid_ad)) | Q(Exists(plan))


def banners_near(latitude, longitude, limit=5):
    """Running banners whose own reach (radius_m) covers the customer. Counts an impression for each."""
    point = make_point(latitude, longitude)
    ads = list(
        running(Placement.HOME_BANNER)
        .filter(shop__status="approved", shop__is_temporarily_closed=False, shop__location__dwithin=(point, F("radius_m")))
        .select_related("shop")
        .order_by("?")[:limit]
    )
    Advertisement.objects.filter(pk__in=[ad.pk for ad in ads]).update(impressions=F("impressions") + 1)
    return ads


def record_click(ad_id):
    return Advertisement.objects.filter(pk=ad_id).update(clicks=F("clicks") + 1)


def expire_ads():
    return Advertisement.objects.filter(status=Status.ACTIVE, ends_at__lte=timezone.now()).update(
        status=Status.EXPIRED, updated_at=timezone.now()
    )
