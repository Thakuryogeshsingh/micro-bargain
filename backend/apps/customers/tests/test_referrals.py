from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.customers.models import CustomerProfile
from apps.orders.models import Coupon
from apps.reservations import services as reservations

REFERRAL = "/api/v1/customers/referral/"


def buy(customer, deal, quantity="1", pickup_at=None):
    reservation = reservations.create_reservation(customer, deal.id, Decimal(quantity), pickup_at)
    reservations.confirm(reservation)
    return reservations.complete(reservation, reservation.pickup_code)


@pytest.mark.django_db
class TestReferral:
    def test_both_rewarded_after_first_purchase_only(self, auth_client, live_deal):
        referrer_client, referrer = auth_client()
        code = referrer_client.get(REFERRAL).data["code"]
        friend_client, friend = auth_client()
        assert friend_client.post(REFERRAL, {"code": code.lower()}).data["applied"] is True

        deal = live_deal()
        buy(friend, deal)
        rewards = Coupon.objects.filter(code__startswith="REF")
        assert sorted(c.customer_id for c in rewards) == sorted([referrer.id, friend.id])
        assert all(c.value == Decimal("50") for c in rewards)
        assert referrer.notifications.filter(kind="referral_reward").exists()

        buy(friend, deal)  # second purchase: nothing new
        assert rewards.count() == 2
        assert referrer_client.get(REFERRAL).data["friends_rewarded"] == 1

    def test_rules(self, auth_client, live_deal):
        client, user = auth_client()
        own = client.get(REFERRAL).data["code"]
        assert client.post(REFERRAL, {"code": own}).data["error"]["code"] == "referral_self"
        assert client.post(REFERRAL, {"code": "NOPE123"}).data["error"]["code"] == "referral_invalid"
        buy(user, live_deal())
        friend_client, _ = auth_client()
        code = friend_client.get(REFERRAL).data["code"]
        assert client.post(REFERRAL, {"code": code}).data["error"]["code"] == "referral_not_new"

    def test_code_at_signup(self, api_client, auth_client, settings):
        settings.SMS_BACKEND = "console"
        referrer_client, _ = auth_client()
        code = referrer_client.get(REFERRAL).data["code"]
        otp = api_client.post("/api/v1/auth/send-otp/", {"phone": "9876500200"}).data["test_otp"]
        data = api_client.post("/api/v1/auth/verify-otp/", {"phone": "9876500200", "code": otp, "referral_code": code}).data
        assert data["is_new_user"] and data["referral_applied"]

    def test_personal_coupon_only_for_owner(self, auth_client):
        _, owner = auth_client()
        stranger_client, _ = auth_client()
        now = timezone.now()
        Coupon.objects.create(code="REFMINE1", customer=owner, discount_type="flat", value=50,
                              valid_from=now, valid_until=now + timedelta(days=1))
        assert "REFMINE1" not in [o["code"] for o in stranger_client.get("/api/v1/orders/offers/").data]


@pytest.mark.django_db
class TestOffersAndPickup:
    def test_offers_list_and_first_order_rule(self, auth_client, live_deal):
        from django.core.management import call_command

        call_command("seed_demo")
        client, user = auth_client()
        codes = [o["code"] for o in client.get("/api/v1/orders/offers/").data]
        assert {"PEHLA50", "BHARAT10", "FRESH20"} <= set(codes)
        buy(user, live_deal())
        codes = [o["code"] for o in client.get("/api/v1/orders/offers/").data]
        assert "PEHLA50" not in codes  # first order is done

    def test_pickup_time_extends_hold(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        pickup = timezone.now() + timedelta(minutes=90)
        data = client.post("/api/v1/reservations/create/", {"deal": deal.id, "quantity": "1", "pickup_at": pickup.isoformat()}).data
        assert data["pickup_at"] is not None
        expires = timezone.datetime.fromisoformat(data["expires_at"])
        assert expires >= pickup + timedelta(minutes=29)

    def test_pickup_after_deal_ends_rejected(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()  # ends in 2 hours
        late = (timezone.now() + timedelta(hours=5)).isoformat()
        response = client.post("/api/v1/reservations/create/", {"deal": deal.id, "quantity": "1", "pickup_at": late})
        assert response.data["error"]["code"] == "invalid_pickup_time"
