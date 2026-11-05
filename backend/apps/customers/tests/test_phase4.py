from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.customers import services as customers
from apps.deals.models import Deal
from apps.notifications import services as notifications
from apps.orders import services as orders
from apps.reservations import services as reservations


def buy(customer, deal, quantity="2"):
    reservation = reservations.create_reservation(customer, deal.id, Decimal(quantity))
    reservations.confirm(reservation)
    reservations.complete(reservation, reservation.pickup_code)
    return reservation


@pytest.mark.django_db
class TestWallet:
    def test_cashback_on_pickup(self, auth_client, live_deal):
        client, customer = auth_client()
        buy(customer, live_deal())  # 2 x 60 = 120 -> 2% = 2.40
        data = client.get("/api/v1/customers/wallet/").data
        assert data["balance"] == Decimal("2.40") and data["entries"][0]["kind"] == "cashback"
        assert customer.notifications.filter(kind="cashback").exists()

    def test_cashback_is_capped(self, auth_client, live_deal):
        _, customer = auth_client()
        buy(customer, live_deal(quantity_total=Decimal("100")), quantity="30")  # 1800 -> 36, cap 25
        assert customers.wallet_balance(customer) == Decimal("25")

    def test_used_on_order_and_returned_on_cancel(self, auth_client, live_deal):
        client, customer = auth_client()
        customers.return_wallet(customer, Decimal("100"), "seed")
        deal = live_deal()
        order = client.post("/api/v1/orders/create/", {
            "items": [{"deal": deal.id, "quantity": "2"}], "payment_method": "cash", "fulfilment": "pickup", "use_wallet": True,
        }, format="json").data
        # at most half of the 120 subtotal
        assert order["wallet_used"] == "60.00" and order["total_amount"] == "60.00"
        assert customers.wallet_balance(customer) == Decimal("40")
        orders.cancel_by_customer(orders.Order.objects.get(pk=order["id"]))
        assert customers.wallet_balance(customer) == Decimal("100")

    def test_not_used_unless_asked(self, auth_client, live_deal):
        client, customer = auth_client()
        customers.return_wallet(customer, Decimal("10"), "seed")
        order = client.post("/api/v1/orders/create/", {
            "items": [{"deal": live_deal().id, "quantity": "1"}], "payment_method": "cash", "fulfilment": "pickup",
        }, format="json").data
        assert order["wallet_used"] == "0.00" and customers.wallet_balance(customer) == Decimal("10")


@pytest.mark.django_db
def test_deal_ending_alert_once_to_fans(live_deal, merchant_shop, auth_client):
    client, shop, product = merchant_shop()
    _, fan = auth_client()
    _, stranger = auth_client()
    shop.favorited_by.create(user=fan)
    deal = live_deal((client, shop, product))
    Deal.objects.filter(pk=deal.pk).update(expires_at=timezone.now() + timedelta(minutes=30))
    assert notifications.deal_ending_alerts() == 1
    assert notifications.deal_ending_alerts() == 0
    assert fan.notifications.filter(kind="deal_ending").count() == 1
    assert not stranger.notifications.exists()


@pytest.mark.django_db
def test_review_with_photo(auth_client, live_deal):
    from django.core.files.uploadedfile import SimpleUploadedFile

    client, customer = auth_client()
    reservation = buy(customer, live_deal())
    gif = b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"
    photo = SimpleUploadedFile("fresh.gif", gif, content_type="image/gif")
    response = client.post("/api/v1/reviews/create/", {"reservation": reservation.id, "rating": 5, "photo": photo}, format="multipart")
    assert response.status_code == 201, response.data
    assert response.data["photo"]


@pytest.mark.django_db
def test_leaderboard_ranks_by_savings(auth_client, live_deal, merchant_shop, api_client):
    _, customer = auth_client()
    small = live_deal(merchant_shop(name="Small"))
    big = live_deal(merchant_shop(name="Big"))
    buy(customer, small, "1")  # saved 40
    buy(customer, big, "3")  # saved 120
    rows = api_client.get("/api/v1/shops/leaderboard/", {"latitude": 27.2152, "longitude": 77.4890}).data
    assert [r["shop"]["name"] for r in rows] == ["Big", "Small"]
    assert rows[0]["rank"] == 1 and rows[0]["savings"] == Decimal("120.00")
