"""Khata, daily subscriptions, chat, cross-shop search and the shop QR poster."""
from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.daily.models import DailyOrder


@pytest.mark.django_db
class TestKhata:
    def test_balance_and_total_due(self, merchant_shop):
        client, _, _ = merchant_shop()
        customer = client.post("/api/v1/khata/customers/", {"name": "Ramu Kaka", "phone": "9812345678"}).data
        url = f"/api/v1/khata/customers/{customer['id']}/entries/"
        client.post(url, {"kind": "credit", "amount": "500", "note": "राशन"})
        assert client.post(url, {"kind": "payment", "amount": "200"}).data["balance"] == Decimal("300.00")
        data = client.get("/api/v1/khata/customers/").data
        assert data["total_due"] == Decimal("300.00") and data["customers"][0]["balance"] == "300.00"
        detail = client.get(f"/api/v1/khata/customers/{customer['id']}/").data
        assert [e["kind"] for e in detail["entries"]] == ["payment", "credit"]
        assert client.delete(f"/api/v1/khata/customers/{customer['id']}/").status_code == 400  # still owes

    def test_other_shop_cannot_see(self, merchant_shop):
        client, _, _ = merchant_shop()
        other, _, _ = merchant_shop()
        customer = client.post("/api/v1/khata/customers/", {"name": "A"}).data
        assert other.get(f"/api/v1/khata/customers/{customer['id']}/").status_code == 404

    def test_customers_cannot_use_khata(self, auth_client):
        client, _ = auth_client()
        assert client.get("/api/v1/khata/customers/").status_code == 403


@pytest.mark.django_db
class TestDaily:
    def test_subscribe_list_deliver_and_bill(self, auth_client, merchant_shop):
        client, customer = auth_client()
        merchant, shop, product = merchant_shop()
        products = client.get("/api/v1/daily/products/", {"shop": shop.id}).data
        assert products[0]["id"] == product.id
        daily = client.post("/api/v1/daily/", {"product": product.id, "quantity": "2", "weekdays": "1111111"}).data
        assert daily["price"] == "100.00" and shop.merchant.user.notifications.filter(kind="daily_order").exists()
        assert client.post("/api/v1/daily/", {"product": product.id, "quantity": "1"}).status_code == 400  # duplicate

        today = merchant.get("/api/v1/daily/shop/").data
        assert today["count"] == 1 and today["items"][0]["delivery"] is None
        done = merchant.post(f"/api/v1/daily/shop/{daily['id']}/deliver/", {"delivered": True}).data
        assert done["month_total"] == "200.00"
        assert client.get("/api/v1/daily/").data[0]["month_total"] == "200.00"

    def test_pause_and_weekdays(self, auth_client, merchant_shop):
        client, _ = auth_client()
        merchant, _, product = merchant_shop()
        today = timezone.localdate()
        off = "".join("0" if i == today.weekday() else "1" for i in range(7))
        daily = client.post("/api/v1/daily/", {"product": product.id, "quantity": "1", "weekdays": off}).data
        assert merchant.get("/api/v1/daily/shop/").data["count"] == 0  # not today
        DailyOrder.objects.filter(pk=daily["id"]).update(weekdays="1111111")
        client.post(f"/api/v1/daily/{daily['id']}/status/", {"status": "paused", "paused_until": str(today + timedelta(days=2))})
        assert merchant.get("/api/v1/daily/shop/").data["count"] == 0  # paused
        later = today + timedelta(days=3)
        assert merchant.get("/api/v1/daily/shop/", {"date": str(later)}).data["count"] == 1  # pause over


@pytest.mark.django_db
class TestChat:
    def test_conversation_both_ways(self, auth_client, merchant_shop):
        client, customer = auth_client()
        merchant, shop, _ = merchant_shop()
        chat = client.post("/api/v1/chat/start/", {"shop": shop.id}).data
        url = f"/api/v1/chat/{chat['id']}/messages/"
        client.post(url, {"text": "भैया पनीर ताज़ा है?"})
        assert shop.merchant.user.notifications.filter(kind="new_message").exists()
        inbox = merchant.get("/api/v1/chat/").data
        assert inbox[0]["unread"] == 1 and inbox[0]["last_message"] == "भैया पनीर ताज़ा है?"
        seen = merchant.get(url).data
        assert seen["messages"][0]["mine"] is False
        assert merchant.get("/api/v1/chat/").data[0]["unread"] == 0
        reply = merchant.post(url, {"text": "हाँ, अभी आया है"}).data
        new = client.get(url, {"after": seen["messages"][0]["id"]}).data["messages"]
        assert [m["id"] for m in new] == [reply["id"]] and customer.notifications.filter(kind="new_message").exists()

    def test_strangers_cannot_read(self, auth_client, merchant_shop):
        client, _ = auth_client()
        stranger, _ = auth_client()
        _, shop, _ = merchant_shop()
        chat = client.post("/api/v1/chat/start/", {"shop": shop.id}).data
        assert stranger.get(f"/api/v1/chat/{chat['id']}/messages/").status_code == 404


@pytest.mark.django_db
def test_search_understands_english_words(api_client, live_deal, merchant_shop):
    from apps.products.models import Product

    client, shop, _ = merchant_shop()
    paneer = Product.objects.create(shop=shop, category=shop.category, name="पनीर", unit="kg", standard_price=400)
    live_deal((client, shop, paneer), normal_price=Decimal("400"), offer_price=Decimal("300"))
    live_deal()  # apples elsewhere
    params = {"latitude": 27.2152, "longitude": 77.4890, "radius": 5000, "sort": "price"}
    names = [d["product_name"] for d in api_client.get("/api/v1/deals/nearby/", {**params, "q": "paneer"}).data["results"]]
    assert names == ["पनीर"]
    assert api_client.get("/api/v1/deals/nearby/", {**params, "q": "Paneer"}).data["count"] == 1


@pytest.mark.django_db
def test_shop_page_and_qr_poster(client, live_deal):
    deal = live_deal()
    page = client.get(f"/s/{deal.shop.id}/").content.decode()
    assert "microbargain://open/shop/" in page and deal.product.name in page
    poster = client.get(f"/s/{deal.shop.id}/poster/").content.decode()
    assert "<svg" in poster and deal.shop.name in poster
