import threading
from datetime import timedelta
from decimal import Decimal

import pytest
from django.db import IntegrityError, connection, transaction
from django.utils import timezone

from apps.deals import services
from apps.deals.models import Deal, DealChangeLog
from common.exceptions import BusinessRuleError
from conftest import BHARATPUR

LAT, LNG = BHARATPUR
CREATE = "/api/v1/deals/create/"
NEARBY = "/api/v1/deals/nearby/"


def deal_payload(shop, product, **extra):
    return {
        "shop": shop.id, "product": product.id, "normal_price": "100.00", "offer_price": "60.00",
        "quantity_total": "20", "duration_minutes": 120, "publish": True, **extra,
    }


@pytest.fixture
def live_deal(merchant_shop):
    """live_deal(lat, lng, **deal fields) -> (merchant client, deal) with a published deal."""

    def _make(lat=LAT, lng=LNG, product_name="सेब (शिमला)", **fields):
        client, shop, product = merchant_shop(lat, lng, product_name=product_name)
        data = {"normal_price": Decimal("100"), "offer_price": Decimal("60"), "quantity_total": Decimal("20"),
                "duration_minutes": 120, **fields}
        deal = services.create_deal(shop.merchant.user, shop=shop, product=product, publish=True, **data)
        return client, deal

    return _make


def nearby(client, radius=2000, **params):
    return client.get(NEARBY, {"latitude": LAT, "longitude": LNG, "radius": radius, **params})


@pytest.mark.django_db
class TestCreateDeal:
    def test_create_and_publish_calculates_discount(self, merchant_shop):
        client, shop, product = merchant_shop()
        response = client.post(CREATE, deal_payload(shop, product))
        assert response.status_code == 201, response.data
        assert response.data["discount_percent"] == "40.00"
        assert response.data["status"] == "active"
        assert response.data["unit"] == "kg"
        assert Decimal(response.data["quantity_available"]) == 20
        assert 7100 < response.data["seconds_left"] <= 7200

    def test_normal_price_defaults_to_product_price(self, merchant_shop):
        client, shop, product = merchant_shop()
        payload = deal_payload(shop, product)
        del payload["normal_price"]
        assert client.post(CREATE, payload).data["normal_price"] == "100.00"

    def test_draft_when_not_publishing(self, merchant_shop):
        client, shop, product = merchant_shop()
        assert client.post(CREATE, deal_payload(shop, product, publish=False)).data["status"] == "draft"

    @pytest.mark.parametrize("offer", ["100.00", "120.00", "0.00"])
    def test_offer_must_be_below_normal(self, merchant_shop, offer):
        client, shop, product = merchant_shop()
        response = client.post(CREATE, deal_payload(shop, product, offer_price=offer))
        assert response.data["error"]["code"] == "invalid_price"

    def test_expiry_rules(self, merchant_shop):
        client, shop, product = merchant_shop()
        past = (timezone.now() - timedelta(minutes=5)).isoformat()
        too_long = (timezone.now() + timedelta(hours=72)).isoformat()
        for expires_at in (past, too_long):
            payload = deal_payload(shop, product, expires_at=expires_at)
            del payload["duration_minutes"]
            assert client.post(CREATE, payload).data["error"]["code"] == "invalid_time"
        payload = deal_payload(shop, product)
        del payload["duration_minutes"]
        assert client.post(CREATE, payload).data["error"]["code"] == "invalid_time"

    def test_cannot_use_another_merchants_product(self, merchant_shop):
        client, shop, _ = merchant_shop()
        _, _, other_product = merchant_shop(name="Other")
        assert client.post(CREATE, deal_payload(shop, other_product)).status_code == 400

    def test_pending_shop_cannot_publish(self, merchant_shop):
        client, shop, product = merchant_shop(approved=False)
        assert client.post(CREATE, deal_payload(shop, product)).data["error"]["code"] == "shop_not_live"

    def test_delivery_needs_shop_delivery(self, merchant_shop):
        client, shop, product = merchant_shop()
        response = client.post(CREATE, deal_payload(shop, product, fulfilment="delivery"))
        assert response.data["error"]["code"] == "delivery_off"

    def test_customer_cannot_create(self, auth_client, merchant_shop):
        _, shop, product = merchant_shop()
        client, _ = auth_client()
        assert client.post(CREATE, deal_payload(shop, product)).status_code == 403

    def test_database_refuses_overbooking(self, live_deal):
        _, deal = live_deal()
        deal.quantity_reserved = Decimal("25")
        with pytest.raises(IntegrityError), transaction.atomic():
            deal.save()


@pytest.mark.django_db
class TestDealManagement:
    def test_pause_hides_and_republish_shows(self, live_deal, api_client):
        client, deal = live_deal()
        assert client.post(f"/api/v1/deals/{deal.id}/pause/").data["status"] == "paused"
        assert nearby(api_client).data["count"] == 0
        assert client.post(f"/api/v1/deals/{deal.id}/publish/").data["status"] == "active"
        assert nearby(api_client).data["count"] == 1

    def test_mark_sold_out_and_end(self, live_deal):
        client, deal = live_deal()
        assert client.post(f"/api/v1/deals/{deal.id}/sold-out/").data["status"] == "sold_out"
        assert client.post(f"/api/v1/deals/{deal.id}/end/").data["status"] == "ended"
        response = client.patch(f"/api/v1/deals/update/{deal.id}/", {"offer_price": "50.00"})
        assert response.data["error"]["code"] == "deal_closed"

    def test_update_price_is_logged(self, live_deal):
        client, deal = live_deal()
        response = client.patch(f"/api/v1/deals/update/{deal.id}/", {"offer_price": "50.00"})
        assert response.data["discount_percent"] == "50.00"
        log = DealChangeLog.objects.get(deal=deal, field="offer_price")
        assert (log.old_value, log.new_value) == ("60.00", "50.00")

    def test_update_rejects_bad_price(self, live_deal):
        client, deal = live_deal()
        response = client.patch(f"/api/v1/deals/update/{deal.id}/", {"offer_price": "150.00"})
        assert response.data["error"]["code"] == "invalid_price"

    def test_stock_update_rules(self, live_deal):
        client, deal = live_deal()
        with transaction.atomic():
            services.reserve_quantity(deal.id, Decimal("5"))
        url = f"/api/v1/deals/{deal.id}/update-stock/"
        assert client.post(url, {"quantity_total": "4"}).data["error"]["code"] == "stock_below_committed"
        response = client.post(url, {"quantity_total": "5"})
        assert response.data["status"] == "sold_out"
        response = client.post(url, {"quantity_total": "8"})
        assert response.data["status"] == "active"
        assert Decimal(response.data["quantity_available"]) == 3

    def test_other_merchant_gets_404(self, live_deal, merchant_shop):
        _, deal = live_deal()
        other, _, _ = merchant_shop(name="Other")
        assert other.post(f"/api/v1/deals/{deal.id}/pause/").status_code == 404
        assert other.patch(f"/api/v1/deals/update/{deal.id}/", {"offer_price": "1.00"}).status_code == 404

    def test_duplicate_makes_new_draft(self, live_deal):
        client, deal = live_deal()
        response = client.post(f"/api/v1/deals/{deal.id}/duplicate/")
        assert response.status_code == 201
        assert response.data["status"] == "draft" and response.data["id"] != deal.id
        assert response.data["offer_price"] == "60.00"

    def test_merchant_list_only_own(self, live_deal):
        client, _ = live_deal()
        other_client, _ = live_deal(product_name="केले")
        assert client.get("/api/v1/deals/").data["count"] == 1
        assert other_client.get("/api/v1/deals/").data["results"][0]["product_name"] == "केले"

    def test_dashboard(self, live_deal):
        client, deal = live_deal()
        with transaction.atomic():
            services.reserve_quantity(deal.id, Decimal("4"))
            services.complete_quantity(deal.id, Decimal("4"))
        stats = client.get("/api/v1/merchants/dashboard/").data
        assert stats["active_deals"] == 1 and stats["total_deals"] == 1
        assert stats["remaining_stock"] == Decimal("16")
        assert stats["revenue"] == Decimal("240")


@pytest.mark.django_db
class TestNearbyDeals:
    def test_radius(self, live_deal, api_client):
        live_deal(LAT + 0.0045, LNG, product_name="0.5 km")
        live_deal(LAT + 0.017, LNG, product_name="1.9 km")
        live_deal(LAT + 0.04, LNG, product_name="4.4 km")
        names = [d["product_name"] for d in nearby(api_client, radius=2000).data["results"]]
        assert names == ["0.5 km", "1.9 km"]
        assert nearby(api_client, radius=1000).data["count"] == 1
        assert nearby(api_client, radius=5000).data["count"] == 3
        first = nearby(api_client).data["results"][0]
        assert 400 < first["distance_m"] < 600
        assert first["shop"]["name"] == "Gupta Fruits"

    def test_hides_drafts_expired_and_sold_out(self, live_deal, merchant_shop, api_client):
        _, expired = live_deal()
        Deal.objects.filter(pk=expired.pk).update(expires_at=timezone.now() - timedelta(seconds=1),
                                                  starts_at=timezone.now() - timedelta(hours=1))
        _, sold = live_deal()
        with transaction.atomic():
            services.reserve_quantity(sold.id, Decimal("20"))
        _, shop, product = merchant_shop()
        services.create_deal(shop.merchant.user, shop=shop, product=product, offer_price=Decimal("50"),
                             quantity_total=Decimal("5"), duration_minutes=60)
        assert nearby(api_client).data["count"] == 0

    def test_hides_closed_shop(self, live_deal, api_client):
        _, deal = live_deal()
        deal.shop.is_temporarily_closed = True
        deal.shop.save()
        assert nearby(api_client).data["count"] == 0

    def test_filters_and_sorting(self, live_deal, api_client):
        live_deal(LAT + 0.001, LNG, product_name="Apple", offer_price=Decimal("60"))   # 40% off
        live_deal(LAT + 0.005, LNG, product_name="Tomato", offer_price=Decimal("30"))  # 70% off
        live_deal(LAT + 0.009, LNG, product_name="Bread", offer_price=Decimal("90"))   # 10% off

        by_price = [d["product_name"] for d in nearby(api_client, sort="price").data["results"]]
        assert by_price == ["Tomato", "Apple", "Bread"]
        by_discount = [d["product_name"] for d in nearby(api_client, sort="discount").data["results"]]
        assert by_discount == ["Tomato", "Apple", "Bread"]
        assert nearby(api_client, min_discount=35).data["count"] == 2
        assert nearby(api_client, max_price=50).data["count"] == 1
        assert [d["product_name"] for d in nearby(api_client, q="tom").data["results"]] == ["Tomato"]

    def test_query_validation(self, api_client):
        assert api_client.get(NEARBY).status_code == 400
        assert nearby(api_client, radius=3000).status_code == 400
        assert nearby(api_client, sort="random").status_code == 400

    def test_detail_and_shop_deals(self, live_deal, api_client):
        _, deal = live_deal()
        detail = api_client.get(f"/api/v1/deals/{deal.id}/").data
        assert detail["offer_price"] == "60.00"
        assert "quantity_reserved" not in detail  # stock breakdown is for the merchant only
        assert api_client.get(f"/api/v1/deals/shop/{deal.shop_id}/").data["count"] == 1

    def test_drafts_are_private(self, merchant_shop, api_client):
        client, shop, product = merchant_shop()
        draft = services.create_deal(shop.merchant.user, shop=shop, product=product, offer_price=Decimal("50"),
                                     quantity_total=Decimal("5"), duration_minutes=60)
        assert api_client.get(f"/api/v1/deals/{draft.id}/").status_code == 404
        owner_view = client.get(f"/api/v1/deals/{draft.id}/").data
        assert owner_view["status"] == "draft" and "quantity_reserved" in owner_view


@pytest.mark.django_db
class TestExpiryAndStock:
    def test_expire_job(self, live_deal):
        _, deal = live_deal()
        _, still_running = live_deal()
        Deal.objects.filter(pk=deal.pk).update(expires_at=timezone.now() - timedelta(seconds=1),
                                               starts_at=timezone.now() - timedelta(hours=1))
        assert services.expire_deals() == 1
        deal.refresh_from_db()
        still_running.refresh_from_db()
        assert deal.status == "expired" and still_running.status == "active"

    def test_reserve_more_than_available(self, live_deal):
        _, deal = live_deal()
        with pytest.raises(BusinessRuleError) as exc, transaction.atomic():
            services.reserve_quantity(deal.id, Decimal("21"))
        assert exc.value.detail.code == "insufficient_stock"

    def test_release_brings_back_sold_out_deal(self, live_deal):
        _, deal = live_deal()
        with transaction.atomic():
            deal = services.reserve_quantity(deal.id, Decimal("20"))
        assert deal.status == "sold_out"
        with transaction.atomic():
            deal = services.release_quantity(deal.id, Decimal("5"))
        assert deal.status == "active" and deal.quantity_available == 5


@pytest.mark.django_db(transaction=True, serialized_rollback=True)
def test_two_customers_reserving_last_unit(live_deal):
    """Doc 19.4: only one of two simultaneous reservations for the final unit may succeed."""
    _, deal = live_deal(quantity_total=Decimal("1"))
    barrier = threading.Barrier(2)
    results = []

    def reserve():
        try:
            barrier.wait()
            with transaction.atomic():
                services.reserve_quantity(deal.id, Decimal("1"))
            results.append("ok")
        except BusinessRuleError as exc:
            results.append(exc.detail.code)
        finally:
            connection.close()

    threads = [threading.Thread(target=reserve) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert results.count("ok") == 1
    deal.refresh_from_db()
    assert deal.quantity_reserved == 1 and deal.status == "sold_out"
