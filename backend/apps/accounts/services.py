"""Business logic for the accounts app: OTP login and JWT tokens."""
import hashlib
import hmac
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import models, transaction
from django.utils import timezone
from rest_framework.exceptions import Throttled
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from common.exceptions import BusinessRuleError

from .models import PhoneOTP, User
from .sms import send_sms


def _hash_code(phone, code):
    key = settings.SECRET_KEY.encode()
    return hmac.new(key, f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def send_otp(phone):
    now = timezone.now()
    recent = PhoneOTP.objects.filter(phone=phone, created_at__gte=now - timedelta(hours=1))
    if recent.count() >= settings.OTP_MAX_PER_HOUR:
        raise Throttled(detail="Too many OTP requests for this number. Try again later.")
    last = recent.first()
    if last and (now - last.created_at).total_seconds() < settings.OTP_RESEND_COOLDOWN_SECONDS:
        raise Throttled(
            wait=settings.OTP_RESEND_COOLDOWN_SECONDS,
            detail="Please wait a few seconds before requesting another OTP.",
        )

    code = "".join(secrets.choice("0123456789") for _ in range(settings.OTP_LENGTH))
    with transaction.atomic():
        PhoneOTP.objects.filter(phone=phone, is_used=False).update(is_used=True)
        otp = PhoneOTP.objects.create(
            phone=phone,
            code_hash=_hash_code(phone, code),
            expires_at=now + timedelta(seconds=settings.OTP_EXPIRY_SECONDS),
        )
    minutes = settings.OTP_EXPIRY_SECONDS // 60
    send_sms(phone, f"{code} is your Micro Bargain login OTP. Valid for {minutes} minutes.", otp=code)
    otp.code = code  # not stored; only for test_otp_for() below
    return otp


def test_otp_for(phone, otp):
    """On a test server without real SMS (SMS_BACKEND=console) the app receives the OTP itself and shows it as a
    notification. Never for staff/admin numbers: anyone could then log in as admin. Never with a real SMS provider."""
    if settings.SMS_BACKEND != "console":
        return None
    if User.objects.filter(phone=phone).filter(models.Q(is_staff=True) | models.Q(role=User.Role.ADMIN)).exists():
        return None
    return otp.code


def verify_otp(phone, code):
    """Check the code and log the user in, creating the account on first login.

    Returns (user, created). Wrong attempts are saved before the error is raised,
    so they are not rolled back.
    """
    error = None
    with transaction.atomic():
        otp = PhoneOTP.objects.select_for_update().filter(phone=phone, is_used=False).first()
        if otp is None or otp.is_expired:
            error = ("OTP has expired. Please request a new one.", "otp_expired")
        elif otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            error = ("Too many wrong attempts. Please request a new OTP.", "otp_locked")
        elif not hmac.compare_digest(otp.code_hash, _hash_code(phone, code)):
            otp.attempts += 1
            otp.save(update_fields=["attempts"])
            error = ("Incorrect OTP.", "otp_invalid")
        else:
            otp.is_used = True
            otp.save(update_fields=["is_used"])
            user, created = _get_or_create_user(phone)

    if error:
        raise BusinessRuleError(*error)
    if not user.is_active:
        raise BusinessRuleError("This account has been disabled. Contact support.", "account_disabled")
    return user, created


def _get_or_create_user(phone):
    from apps.customers.models import CustomerProfile

    user = User.objects.filter(phone=phone).first()
    created = user is None
    if created:
        user = User.objects.create_user(phone=phone)
    user.is_phone_verified = True
    user.last_login = timezone.now()
    user.save(update_fields=["is_phone_verified", "last_login"])
    if user.is_customer:
        CustomerProfile.objects.get_or_create(user=user)
    return user, created


def issue_tokens(user):
    refresh = RefreshToken.for_user(user)
    refresh["role"] = user.role
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


def logout(refresh_token):
    try:
        RefreshToken(refresh_token).blacklist()
    except TokenError:
        raise BusinessRuleError("Invalid or expired refresh token.", "invalid_token")


@transaction.atomic
def delete_account(user):
    """Delete an account on the user's request (Play Store / DPDP requirement).

    Orders, reservations and payments are kept for accounting and tax records, but the person is
    anonymised: phone, name and email are wiped, addresses and devices deleted, all sessions ended.
    """
    from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken

    from apps.audit.services import record
    from apps.orders.models import Order
    from apps.reservations.models import DealReservation

    open_orders = Order.objects.filter(customer=user, status__in=Order.OPEN_STATUSES).exists()
    open_reservations = DealReservation.objects.filter(customer=user, status__in=DealReservation.OPEN_STATUSES).exists()
    if open_orders or open_reservations:
        raise BusinessRuleError("Finish or cancel your open orders and reservations first.", "open_bookings")

    if hasattr(user, "merchant_profile"):
        from apps.deals.models import Deal

        shops = user.merchant_profile.shops.all()
        if Order.objects.filter(shop__in=shops, status__in=Order.OPEN_STATUSES).exists() or DealReservation.objects.filter(
            shop__in=shops, status__in=DealReservation.OPEN_STATUSES
        ).exists():
            raise BusinessRuleError("Your shop has open orders or reservations. Complete them first.", "open_bookings")
        Deal.objects.filter(shop__in=shops).exclude(status__in=Deal.FINAL_STATUSES).update(status=Deal.Status.ENDED)
        shops.update(is_temporarily_closed=True, phone="")

    record(user, "account.deleted", user)
    user.addresses.all().delete()
    user.devices.all().delete()
    user.favorite_shops.all().delete()
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)

    # "0" + 9 digits can never be a real Indian mobile number, so the phone is free to register again.
    user.phone = f"0{user.id:09d}"
    user.name = ""
    user.email = ""
    user.is_active = False
    user.set_unusable_password()
    user.save()
