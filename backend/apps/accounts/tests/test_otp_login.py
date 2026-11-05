import re
from datetime import timedelta
from unittest import mock

import pytest
from django.utils import timezone

from apps.accounts.models import PhoneOTP, User
from apps.customers.models import CustomerProfile

SEND = "/api/v1/auth/send-otp/"
VERIFY = "/api/v1/auth/verify-otp/"


def send_and_capture(client, phone="9876543210"):
    """Request an OTP and return the code that would have gone by SMS."""
    with mock.patch("apps.accounts.services.send_sms") as sms:
        response = client.post(SEND, {"phone": phone})
    assert response.status_code == 200, response.data
    return re.match(r"(\d{6})", sms.call_args.args[1]).group(1)


@pytest.mark.django_db
class TestSendOTP:
    def test_sends_and_stores_only_a_hash(self, api_client):
        code = send_and_capture(api_client)
        otp = PhoneOTP.objects.get(phone="9876543210")
        assert otp.code_hash != code
        assert len(otp.code_hash) == 64

    def test_accepts_country_code_and_spaces(self, api_client):
        send_and_capture(api_client, phone="+91 98765 43210")
        assert PhoneOTP.objects.filter(phone="9876543210").exists()

    @pytest.mark.parametrize("phone", ["12345", "5876543210", "abcdefghij"])
    def test_rejects_invalid_numbers(self, api_client, phone):
        response = api_client.post(SEND, {"phone": phone})
        assert response.status_code == 400
        assert response.data["error"]["code"] == "validation_error"

    def test_resend_cooldown(self, api_client):
        send_and_capture(api_client)
        response = api_client.post(SEND, {"phone": "9876543210"})
        assert response.status_code == 429

    def test_hourly_limit_per_number(self, api_client, settings):
        settings.OTP_RESEND_COOLDOWN_SECONDS = 0
        for _ in range(settings.OTP_MAX_PER_HOUR):
            send_and_capture(api_client)
        response = api_client.post(SEND, {"phone": "9876543210"})
        assert response.status_code == 429

    def test_new_otp_invalidates_old_one(self, api_client, settings):
        settings.OTP_RESEND_COOLDOWN_SECONDS = 0
        old_code = send_and_capture(api_client)
        new_code = send_and_capture(api_client)
        if old_code != new_code:
            response = api_client.post(VERIFY, {"phone": "9876543210", "code": old_code})
            assert response.status_code == 400
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": new_code})
        assert response.status_code in (200, 201)


@pytest.mark.django_db
class TestVerifyOTP:
    def test_first_login_creates_customer(self, api_client):
        code = send_and_capture(api_client)
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.status_code == 201
        assert response.data["is_new_user"] is True
        assert {"access", "refresh"} <= response.data.keys()
        user = User.objects.get(phone="9876543210")
        assert user.role == "customer" and user.is_phone_verified
        assert not user.has_usable_password()
        assert CustomerProfile.objects.filter(user=user).exists()

    def test_second_login_returns_existing_user(self, api_client, make_user):
        make_user(phone="9876543210")
        code = send_and_capture(api_client)
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.status_code == 200
        assert response.data["is_new_user"] is False
        assert User.objects.filter(phone="9876543210").count() == 1

    def test_wrong_code_counts_attempts_and_locks(self, api_client, settings):
        code = send_and_capture(api_client)
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(settings.OTP_MAX_ATTEMPTS):
            response = api_client.post(VERIFY, {"phone": "9876543210", "code": wrong})
            assert response.data["error"]["code"] == "otp_invalid"
        assert PhoneOTP.objects.get(phone="9876543210").attempts == settings.OTP_MAX_ATTEMPTS
        # Even the right code is refused once locked.
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.data["error"]["code"] == "otp_locked"

    def test_expired_code(self, api_client):
        code = send_and_capture(api_client)
        PhoneOTP.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.data["error"]["code"] == "otp_expired"

    def test_code_cannot_be_reused(self, api_client):
        code = send_and_capture(api_client)
        assert api_client.post(VERIFY, {"phone": "9876543210", "code": code}).status_code == 201
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.data["error"]["code"] == "otp_expired"

    def test_disabled_account_cannot_log_in(self, api_client, make_user):
        make_user(phone="9876543210", is_active=False)
        code = send_and_capture(api_client)
        response = api_client.post(VERIFY, {"phone": "9876543210", "code": code})
        assert response.data["error"]["code"] == "account_disabled"


@pytest.mark.django_db
class TestTokensAndProfile:
    def login(self, api_client):
        code = send_and_capture(api_client)
        return api_client.post(VERIFY, {"phone": "9876543210", "code": code}).data

    def test_profile_requires_token(self, api_client):
        assert api_client.get("/api/v1/auth/profile/").status_code == 401

    def test_profile_get_and_update(self, api_client):
        tokens = self.login(api_client)
        api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        response = api_client.patch("/api/v1/auth/profile/update/", {"name": "राहुल", "email": "r@example.com"})
        assert response.status_code == 200
        assert response.data["name"] == "राहुल"
        assert api_client.get("/api/v1/auth/profile/").data["email"] == "r@example.com"

    def test_refresh_then_logout_blacklists_token(self, api_client):
        tokens = self.login(api_client)
        refreshed = api_client.post("/api/v1/auth/refresh/", {"refresh": tokens["refresh"]})
        assert refreshed.status_code == 200
        new_refresh = refreshed.data["refresh"]

        api_client.credentials(HTTP_AUTHORIZATION=f"Bearer {refreshed.data['access']}")
        assert api_client.post("/api/v1/auth/logout/", {"refresh": new_refresh}).status_code == 204
        assert api_client.post("/api/v1/auth/refresh/", {"refresh": new_refresh}).status_code == 401


@pytest.mark.django_db
class TestTestOTP:
    def test_returned_with_console_sms(self, api_client, settings):
        settings.SMS_BACKEND = "console"
        data = api_client.post(SEND, {"phone": "9876500111"}).data
        assert len(data["test_otp"]) == 6
        assert api_client.post(VERIFY, {"phone": "9876500111", "code": data["test_otp"]}).status_code == 201

    def test_never_with_real_sms(self, api_client, settings):
        settings.SMS_BACKEND = "msg91"
        with mock.patch("apps.accounts.services.send_sms"):
            assert "test_otp" not in api_client.post(SEND, {"phone": "9876500112"}).data

    def test_never_for_admin(self, api_client, make_user, settings):
        settings.SMS_BACKEND = "console"
        make_user(role="admin", phone="9876500113", is_staff=True)
        assert "test_otp" not in api_client.post(SEND, {"phone": "9876500113"}).data
