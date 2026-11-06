"""Price alerts, shopping list, mohalla deals, loyalty, broadcasts, campaigns, staff/delivery, low stock, sales, bills."""
from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.customers import services as customers
from apps.growth import services
from apps.growth.models import Broadcast, Campaign, LoyaltyAccount
from apps.orders.models import Coupon
from apps.reservations import services as reservations

LAT, LNG = 27.2152, 77.4890


def buy(customer, deal, qty="2"):
    r = reservations.create_reservation(customer, deal.id, Decimal(qty))
    reservations.confirm(r)
    return reservations.complete(r, r.pickup_code)


@pytest.mark.django_db
class TestPriceAlert:
    def test_notifies_once_when_price_is_low(self, auth_client, live_deal):
        client, user = auth_client()
        live_deal()  # सेब at ₹60
        r = client.post("/api/v1/growth/alerts/", {"query": "apple", "max_price": "70", "latitude": LAT, "longitude": LNG})
        assert r.status_code == 201
        assert user.notifications.filter(kind="price_alert").count() == 1
        assert services.check_price_alerts() == 0  # same deal, no repeat

    def test_no_alert_above_limit(self, auth_client, live_deal):
        client, user = auth_client()
        live_deal()
        client.post("/api/v1/growth/alerts/", {"query": "apple", "max_price": "50", "latitude": LAT, "longitude": LNG})
        assert not user.notifications.filter(kind="price_alert").exists()


@pytest.mark.django_db
def test_shopping_list_best_shop(api_client, live_deal, merchant_shop, fruits):
    from apps.products.models import Product

    client, shop, apple = merchant_shop()
    banana = Product.objects.create(shop=shop, category=fruits, name="केला", unit="dozen", standard_price=60)
    live_deal((client, shop, apple))
    live_deal((client, shop, banana), normal_price=Decimal("60"), offer_price=Decimal("40"))
    data = api_client.post("/api/v1/growth/shopping-list/", {"items": ["apple", "banana", "unicorn"], "latitude": LAT, "longitude": LNG},
                           format="json").data
    assert [len(i["deals"]) for i in data["items"]] == [1, 1, 0]
    assert data["best_shop"]["covers"] == 2 and data["best_shop"]["of"] == 3


@pytest.mark.django_db
def test_group_deal_unlocks_and_pays_bonus(auth_client, live_deal):
    deal = live_deal()
    group = deal.merchant_client.post("/api/v1/growth/groups/start/", {"deal": deal.id, "target": 2, "extra_percent": 10}).data
    first_client, first = auth_client()
    second_client, second = auth_client()
    assert first_client.post(f"/api/v1/growth/groups/{group['id']}/join/").data["unlocked"] is False
    assert second_client.post(f"/api/v1/growth/groups/{group['id']}/join/").data["unlocked"] is True
    assert first.notifications.filter(kind="group_deal").exists()
    before = customers.wallet_balance(first)
    buy(first, deal)  # 2 x 60 = 120 -> 10% = 12 bonus (+ 2% cashback)
    assert customers.wallet_balance(first) - before == Decimal("12") + Decimal("2.40")


@pytest.mark.django_db
class TestLoyalty:
    def test_points_streak_and_redeem(self, auth_client, live_deal):
        client, user = auth_client()
        deal = live_deal(quantity_total=Decimal("100"))
        buy(user, deal, "20")  # ₹1200 -> 120 points
        account = LoyaltyAccount.objects.get(user=user)
        assert account.points == 120 and account.streak_days == 1
        LoyaltyAccount.objects.filter(user=user).update(streak_days=6, last_purchase_date=timezone.localdate() - timedelta(days=1))
        buy(user, deal, "1")  # day 7 -> +50 bonus, +6 points
        data = client.get("/api/v1/growth/loyalty/").data
        assert data["streak_days"] == 7 and data["points"] == 120 + 6 + 50
        before = customers.wallet_balance(user)
        assert client.post("/api/v1/growth/loyalty/", {"points": 100}).data["credited"] == Decimal("10")
        assert customers.wallet_balance(user) - before == Decimal("10")
        assert client.post("/api/v1/growth/loyalty/", {"points": 150}).status_code == 400  # not a multiple of 100


@pytest.mark.django_db
def test_broadcast_and_campaign(auth_client, merchant_shop):
    _, customer = auth_client()
    merchant_shop()
    sent = services.send_broadcast(Broadcast.objects.create(title="दिवाली ऑफ़र", body="सब पर 20% छूट"))
    assert sent >= 1 and customer.notifications.filter(kind="announcement").exists()
    now = timezone.now()
    coupon = Coupon.objects.create(code="DIWALI20", description="d", discount_type="percent", value=20, min_order_amount=0,
                                   valid_from=now, valid_until=now + timedelta(minutes=1), is_active=False)
    Campaign.objects.create(name="Diwali", title="दिवाली धमाका", coupon=coupon, starts_at=now - timedelta(hours=1),
                            ends_at=now + timedelta(days=2), announce=True)
    services.run_campaigns()
    coupon.refresh_from_db()
    assert coupon.is_active and coupon.valid_until > now
    from rest_framework.test import APIClient

    assert APIClient().get("/api/v1/growth/campaigns/").data[0]["coupon"] == "DIWALI20"


@pytest.mark.django_db
class TestStaffAndDelivery:
    def test_helper_handles_orders_delivery_completes_and_shares_location(self, auth_client, live_deal, merchant_shop):
        from rest_framework.test import APIClient

        from apps.accounts.models import User
        from apps.customers.models import Address

        merchant, shop, product = merchant_shop(offers_delivery=True)
        helper = merchant.post("/api/v1/team/", {"phone": "9811111111", "name": "Raju", "kind": "helper"}).data
        rider = merchant.post("/api/v1/team/", {"phone": "9822222222", "name": "Sonu", "kind": "delivery"}).data
        assert len(merchant.get("/api/v1/team/").data) == 2
        helper_client, rider_client = APIClient(), APIClient()
        helper_client.force_authenticate(User.objects.get(phone="9811111111"))
        rider_client.force_authenticate(User.objects.get(phone="9822222222"))
        assert helper_client.get("/api/v1/team/me/").data["job"]["kind"] == "helper"

        client, customer = auth_client()
        address = Address.objects.create(user=customer, address_line="x", city="Bharatpur", state="Rajasthan", pincode="321001",
                                         latitude=27.21, longitude=77.49)
        deal = live_deal((merchant, shop, product), fulfilment="both")
        order = client.post("/api/v1/orders/create/", {"items": [{"deal": deal.id, "quantity": "1"}], "payment_method": "cash",
                                                        "fulfilment": "delivery", "address": address.id}, format="json").data
        assert helper_client.post(f"/api/v1/orders/{order['id']}/accept/").status_code == 200
        assert rider_client.get("/api/v1/orders/").data["count"] == 0  # not assigned yet
        assert helper_client.post(f"/api/v1/orders/{order['id']}/assign/", {"staff": rider["id"]}).status_code == 200
        assert rider_client.post(f"/api/v1/orders/{order['id']}/accept/").status_code == 403  # delivery can only complete
        helper_client.post(f"/api/v1/orders/{order['id']}/ready/")
        assert rider_client.post(f"/api/v1/orders/{order['id']}/location/", {"latitude": "27.2140", "longitude": "77.4880"}).status_code == 204
        seen = client.get(f"/api/v1/orders/{order['id']}/").data
        assert seen["delivery_partner_name"] == "Sonu" and seen["rider_latitude"] is not None
        code = seen["pickup_code"]
        assert rider_client.post(f"/api/v1/orders/{order['id']}/complete/", {"pickup_code": code}).status_code == 200

    def test_shop_owner_numbers_cannot_be_staff(self, merchant_shop):
        merchant, _, _ = merchant_shop()
        _, other, _ = merchant_shop()
        r = merchant.post("/api/v1/team/", {"phone": other.merchant.user.phone, "name": "X"})
        assert r.status_code == 400

    def test_removed_staff_loses_access(self, merchant_shop):
        from rest_framework.test import APIClient

        from apps.accounts.models import User

        merchant, _, _ = merchant_shop()
        job = merchant.post("/api/v1/team/", {"phone": "9833333333", "name": "Ram"}).data
        merchant.delete(f"/api/v1/team/{job['id']}/")
        user = User.objects.get(phone="9833333333")
        assert user.role == "customer"
        c = APIClient()
        c.force_authenticate(user)
        assert c.get("/api/v1/team/me/").data["job"] is None


@pytest.mark.django_db
def test_low_stock_alert(auth_client, live_deal):
    from apps.inventory import services as inventory

    deal = live_deal()
    owner = deal.shop.merchant.user
    inventory.adjust(owner, deal.product, Decimal("5"), "restock", low_stock_threshold=Decimal("4"))
    _, customer = auth_client()
    buy(customer, deal, "2")  # 5 -> 3, crosses 4
    assert owner.notifications.filter(kind="low_stock").count() == 1


@pytest.mark.django_db
def test_sales_report_and_bill(auth_client, live_deal, client):
    deal = live_deal()
    _, customer = auth_client()
    r = buy(customer, deal, "2")
    sales = deal.merchant_client.get("/api/v1/merchants/sales/").data
    assert sales["total"] == Decimal("120.00") and sales["count"] == 1 and len(sales["series"]) == 7
    assert sales["top_products"][0]["name"] == deal.product.name
    token = deal.merchant_client.get(f"/api/v1/reservations/{r.id}/").data["bill_token"]
    page = client.get(f"/bill/{token}/").content.decode()
    assert deal.shop.name in page and "120.00" in page
    assert client.get("/bill/forged-token/").status_code == 404
