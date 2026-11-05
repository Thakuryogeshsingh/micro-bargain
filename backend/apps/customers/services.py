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



# ---------- Bargain Plus ----------

def active_plus(user):
    from .models import PlusMembership

    now = timezone.now()
    return PlusMembership.objects.filter(user=user, status=PlusMembership.Status.ACTIVE, starts_at__lte=now, ends_at__gt=now).first()


def buy_plus(user):
    from .models import PlusMembership

    PlusMembership.objects.filter(user=user, status=PlusMembership.Status.PENDING_PAYMENT).update(status=PlusMembership.Status.CANCELLED)
    return PlusMembership.objects.create(user=user, amount=settings.PLUS_PRICE_RUPEES)


@transaction.atomic
def activate_plus(membership):
    """Payment received: starts now, or after the current membership ends (renewal)."""
    from apps.notifications import services as notifications

    from .models import PlusMembership

    membership = PlusMembership.objects.select_for_update().get(pk=membership.pk)
    if membership.status == PlusMembership.Status.ACTIVE:
        return membership
    current = active_plus(membership.user)
    membership.starts_at = current.ends_at if current else timezone.now()
    membership.ends_at = membership.starts_at + timedelta(days=settings.PLUS_DAYS)
    membership.status = PlusMembership.Status.ACTIVE
    membership.save(update_fields=["status", "starts_at", "ends_at", "updated_at"])
    notifications.notify(
        membership.user, notifications.Kind.PLUS_ACTIVE, "💎 Bargain Plus चालू!",
        f"हर ऑर्डर पर फ्री डिलीवरी और {settings.PLUS_EXTRA_PERCENT}% और छूट — {timezone.localtime(membership.ends_at):%d %b} तक।",
    )
    return membership


def plus_discount(user, subtotal):
    """Extra discount for Plus members, capped."""
    from decimal import ROUND_HALF_UP, Decimal

    if not active_plus(user):
        return Decimal("0")
    value = subtotal * Decimal(settings.PLUS_EXTRA_PERCENT) / 100
    return min(value, Decimal(settings.PLUS_EXTRA_CAP_RUPEES)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


# ---------- impact ----------

def impact(user):
    """Money saved and food rescued by this customer (completed purchases only)."""
    from decimal import Decimal

    from django.db.models import DecimalField, F, Sum
    from django.db.models.functions import Coalesce

    from apps.orders.models import Order, OrderItem
    from apps.reservations.models import DealReservation

    money = DecimalField(max_digits=14, decimal_places=2)
    reservations = DealReservation.objects.filter(customer=user, status=DealReservation.Status.COMPLETED)
    orders = Order.objects.filter(customer=user, status=Order.Status.COMPLETED)
    saved = reservations.aggregate(s=Coalesce(Sum((F("normal_unit_price") - F("unit_price")) * F("quantity"), output_field=money), Decimal(0), output_field=money))["s"]
    saved += orders.aggregate(s=Coalesce(Sum(F("savings") + F("coupon_discount") + F("plus_discount"), output_field=money), Decimal(0), output_field=money))["s"]
    weight_units = ["kg", "litre"]
    kg = reservations.filter(unit__in=weight_units).aggregate(s=Coalesce(Sum("quantity"), Decimal(0), output_field=money))["s"]
    kg += OrderItem.objects.filter(order__in=orders, unit__in=weight_units).aggregate(s=Coalesce(Sum("quantity"), Decimal(0), output_field=money))["s"]
    grams = reservations.filter(unit="g").aggregate(s=Coalesce(Sum("quantity"), Decimal(0), output_field=money))["s"]
    return {
        "money_saved": saved,
        "food_rescued_kg": kg + grams / 1000,
        "purchases": reservations.count() + orders.count(),
    }



# ---------- wallet ----------

def wallet_balance(user, lock=False):
    from decimal import Decimal

    from django.db.models import Sum

    from .models import WalletEntry

    qs = WalletEntry.objects.filter(user=user)
    if lock:
        # Serialise wallet spending per user (customer profile row as the lock).
        from .models import CustomerProfile

        CustomerProfile.objects.select_for_update().get_or_create(user=user)
    return qs.aggregate(s=Sum("amount"))["s"] or Decimal("0")


def credit_cashback(user, purchase_amount, reference):
    """Cashback on a completed purchase. Call inside the completing transaction."""
    from decimal import ROUND_HALF_UP, Decimal

    from apps.notifications import services as notifications

    from .models import WalletEntry

    amount = min(purchase_amount * Decimal(settings.CASHBACK_PERCENT) / 100, Decimal(settings.CASHBACK_CAP_RUPEES))
    amount = amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if amount <= 0:
        return None
    entry = WalletEntry.objects.create(user=user, kind=WalletEntry.Kind.CASHBACK, amount=amount, reference=reference)
    notifications.notify(user, notifications.Kind.CASHBACK, f"💰 ₹{amount} कैशबैक मिला!",
                         f"अगले ऑर्डर में वॉलेट से इस्तेमाल करें ({reference}).", push=notifications.wants_order_updates(user))
    return entry


def use_wallet(user, wanted, reference):
    """Debit up to `wanted` from the wallet; returns the amount actually used."""
    from .models import WalletEntry

    used = min(wanted, wallet_balance(user, lock=True))
    if used > 0:
        WalletEntry.objects.create(user=user, kind=WalletEntry.Kind.USED, amount=-used, reference=reference)
    return used


def return_wallet(user, amount, reference):
    from .models import WalletEntry

    if amount > 0:
        WalletEntry.objects.create(user=user, kind=WalletEntry.Kind.RETURNED, amount=amount, reference=reference)
