"""Business logic for the customers app."""
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from common.exceptions import BusinessRuleError

from .models import Address


@transaction.atomic
def save_address(serializer, user):
    """Create or update an address, keeping at most one default per user."""
    is_new = serializer.instance is None
    if is_new and user.addresses.count() >= settings.MAX_ADDRESSES_PER_CUSTOMER:
        raise BusinessRuleError(
            f"You can save up to {settings.MAX_ADDRESSES_PER_CUSTOMER} addresses.", "address_limit"
        )
    make_default = serializer.validated_data.get("is_default") or (is_new and not user.addresses.exists())
    if make_default:
        Address.objects.filter(user=user, is_default=True).update(is_default=False)
        return serializer.save(user=user, is_default=True)
    return serializer.save(user=user)


# ---------- referrals ----------

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def referral_code(user):
    """The user's own code to share (created on first use)."""
    from .models import CustomerProfile

    profile, _ = CustomerProfile.objects.get_or_create(user=user)
    while not profile.referral_code:
        code = "MB" + "".join(secrets.choice(_CODE_ALPHABET) for _ in range(5))
        if not CustomerProfile.objects.filter(referral_code=code).exists():
            profile.referral_code = code
            profile.save(update_fields=["referral_code", "updated_at"])
    return profile.referral_code


def has_purchased(user):
    from apps.orders.models import Order
    from apps.reservations.models import DealReservation

    return (
        Order.objects.filter(customer=user, status=Order.Status.COMPLETED).exists()
        or DealReservation.objects.filter(customer=user, status=DealReservation.Status.COMPLETED).exists()
    )


@transaction.atomic
def apply_referral(user, code):
    """A new customer enters a friend's code. Allowed once, before the first purchase."""
    from .models import CustomerProfile

    profile, _ = CustomerProfile.objects.select_for_update().get_or_create(user=user)
    if profile.referred_by_id:
        raise BusinessRuleError("A referral code is already applied.", "referral_already_applied")
    if has_purchased(user):
        raise BusinessRuleError("Referral codes are only for new customers.", "referral_not_new")
    referrer = CustomerProfile.objects.filter(referral_code=code.strip().upper()).select_related("user").first()
    if referrer is None:
        raise BusinessRuleError("This referral code is not valid.", "referral_invalid")
    if referrer.user_id == user.id:
        raise BusinessRuleError("You cannot use your own code.", "referral_self")
    profile.referred_by = referrer.user
    profile.save(update_fields=["referred_by", "updated_at"])
    return referrer.user


def reward_referral(customer):
    """Called inside the transaction that completes a purchase: on the first one, reward both friends."""
    from apps.notifications import services as notifications
    from apps.orders.models import Coupon

    from .models import CustomerProfile

    profile = (
        CustomerProfile.objects.select_for_update()
        .filter(user=customer, referred_by__isnull=False, referral_rewarded_at__isnull=True)
        .select_related("referred_by")
        .first()
    )
    if profile is None:
        return []
    now = timezone.now()
    profile.referral_rewarded_at = now
    profile.save(update_fields=["referral_rewarded_at", "updated_at"])
    amount = settings.REFERRAL_REWARD_RUPEES
    coupons = []
    for person in (profile.referred_by, customer):
        code = "REF" + "".join(secrets.choice(_CODE_ALPHABET) for _ in range(6))
        coupons.append(Coupon.objects.create(
            code=code, customer=person, discount_type=Coupon.DiscountType.FLAT, value=amount,
            min_order_amount=settings.REFERRAL_REWARD_MIN_ORDER, valid_from=now,
            valid_until=now + timedelta(days=settings.REFERRAL_REWARD_VALID_DAYS), usage_limit=1,
            description=f"Referral reward: ₹{amount} off on ₹{settings.REFERRAL_REWARD_MIN_ORDER}+",
        ))
        notifications.notify(
            person, notifications.Kind.REFERRAL_REWARD, f"🎁 ₹{amount} का रेफ़रल इनाम!",
            f"कूपन {code} — ₹{settings.REFERRAL_REWARD_MIN_ORDER} से ऊपर के ऑर्डर पर ₹{amount} छूट। {settings.REFERRAL_REWARD_VALID_DAYS} दिन तक।",
            data={"coupon": code},
        )
    return coupons
