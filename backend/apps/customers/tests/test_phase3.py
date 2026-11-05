from datetime import timedelta
from decimal import Decimal
from unittest import mock

import pytest
from django.utils import timezone

from apps.customers.models import PlusMembership
from apps.deals import services as deal_services
from apps.deals.models import Deal
from apps.payments import gateway
from apps.products.models import Product
from apps.reservations import services as reservations


def pay(client, purpose, object_id):
    checkout = client.post("/api/v1/payments/create/", {"purpose": purpose, "id": object_id}).data
    return client.post("/api/v1/payments/verify/", {
        "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": "pay_x",
        "razorpay_signature": gateway.checkout_signature(checkout["razorpay_order_id"], "pay_x"),
    })


@pytest.mark.django_db
class TestHappyHour:
    def test_applies_before_closing_and_restores_after(self, live_deal, merchant_shop, auth_client):
        now = timezone.localtime()
        closing = (now + timedelta(minutes=30)).time().replace(second=0, microsecond=0)
        client, shop, product = merchant_shop(closing_time=closing, happy_hour_enabled=True, happy_hour_percent=20)
        _, fan = auth_client()
        shop.favorited_by.create(user=fan)
        deal = live_deal((client, shop, product))  # 60 instead of 100

        assert deal_services.run_happy_hours() == (1, 0)
        deal.refresh_from_db()
        assert deal.offer_price == Decimal("48") and deal.happy_hour_original_price == Decimal("60")
        assert deal.discount_percent == Decimal("52.00")
        assert fan.notifications.filter(kind="happy_hour").exists()
        assert client.get(f"/api/v1/deals/{deal.id}/").data["is_happy_hour"] is True
        assert deal_services.run_happy_hours() == (0, 0)  # not applied twice

        shop.closing_time = (now - timedelta(minutes=5)).time()
        shop.save()
        assert deal_services.run_happy_hours() == (0, 1)
        deal.refresh_from_db()
        assert deal.offer_price == Decimal("60") and deal.happy_hour_original_price is None

    def test_off_by_default(self, live_deal, merchant_shop):
        closing = (timezone.localtime() + timedelta(minutes=30)).time()
        live_deal(merchant_shop(closing_time=closing))
        assert deal_services.run_happy_hours() == (0, 0)


@pytest.mark.django_db
def test_bought_together_same_shop_only(live_deal, merchant_shop, fruits, api_client):
    client, shop, apple = merchant_shop()
    banana = Product.objects.create(shop=shop, category=fruits, name="केला", unit="dozen", standard_price=60)
    first = live_deal((client, shop, apple))
    second = live_deal((client, shop, banana), normal_price=Decimal("60"), offer_price=Decimal("40"))
    live_deal()  # another shop
    ids = [d["id"] for d in api_client.get(f"/api/v1/deals/{first.id}/together/").data]
    assert ids == [second.id]


@pytest.mark.django_db
def test_impact_counts_money_and_food(auth_client, live_deal):
    client, customer = auth_client()
    reservation = reservations.create_reservation(customer, live_deal().id, Decimal("2"))
    reservations.confirm(reservation)
    reservations.complete(reservation, reservation.pickup_code)
    data = client.get("/api/v1/customers/impact/").data
    assert data["money_saved"] == Decimal("80.00") and data["food_rescued_kg"] == Decimal("2.00") and data["purchases"] == 1


@pytest.mark.django_db
class TestBargainPlus:
    def test_buy_and_order_benefits(self, auth_client, live_deal, merchant_shop):
        client, customer = auth_client()
        assert client.get("/api/v1/customers/plus/").data["active"] is False
        membership = client.post("/api/v1/customers/plus/").data
        assert pay(client, "membership", membership["id"]).status_code == 200
        status = client.get("/api/v1/customers/plus/").data
        assert status["active"] and status["ends_at"] is not None

        from apps.customers.models import Address

        address = Address.objects.create(user=customer, address_line="x", city="Bharatpur", state="Rajasthan",
                                         pincode="321001", latitude=27.21, longitude=77.49)
        deal = live_deal(merchant_shop(offers_delivery=True), fulfilment="both")
        order = client.post("/api/v1/orders/create/", {
            "items": [{"deal": deal.id, "quantity": "2"}], "payment_method": "cash", "fulfilment": "delivery", "address": address.id,
        }, format="json").data
        # 120 subtotal: 5% Plus discount = 6, delivery free for members
        assert order["plus_discount"] == "6.00" and order["delivery_fee"] == "0.00" and order["total_amount"] == "114.00"

    def test_renewal_extends(self, auth_client):
        client, customer = auth_client()
        for _ in range(2):
            pay(client, "membership", client.post("/api/v1/customers/plus/").data["id"])
        first, second = PlusMembership.objects.filter(status="active").order_by("id")
        assert second.starts_at == first.ends_at
