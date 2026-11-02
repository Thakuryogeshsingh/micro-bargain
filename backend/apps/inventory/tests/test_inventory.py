from decimal import Decimal

import pytest

from apps.inventory.models import Inventory
from apps.reservations import services as reservations

ADJUST = "/api/v1/inventory/adjust/"


@pytest.mark.django_db
class TestInventory:
    def test_restock_and_wastage(self, merchant_shop):
        client, _, product = merchant_shop()
        response = client.post(ADJUST, {"product": product.id, "change": "25", "reason": "restock", "low_stock_threshold": "5"})
        assert response.data["quantity_on_hand"] == "25.00"
        response = client.post(ADJUST, {"product": product.id, "change": "-3", "reason": "wastage", "note": "sade hue"})
        assert response.data["quantity_on_hand"] == "22.00"
        movements = client.get(f"/api/v1/inventory/{response.data['id']}/movements/").data["results"]
        assert [m["reason"] for m in movements] == ["wastage", "restock"]

    def test_cannot_go_negative(self, merchant_shop):
        client, _, product = merchant_shop()
        client.post(ADJUST, {"product": product.id, "change": "2", "reason": "restock"})
        response = client.post(ADJUST, {"product": product.id, "change": "-5", "reason": "wastage"})
        assert response.data["error"]["code"] == "insufficient_inventory"

    def test_cannot_touch_other_merchants_product(self, merchant_shop):
        client, _, _ = merchant_shop()
        _, _, other_product = merchant_shop()
        assert client.post(ADJUST, {"product": other_product.id, "change": "5", "reason": "restock"}).status_code == 400

    def test_deal_limited_by_stock_and_sale_deducts(self, merchant_shop, live_deal, auth_client):
        client, shop, product = merchant_shop()
        client.post(ADJUST, {"product": product.id, "change": "10", "reason": "restock", "low_stock_threshold": "9"})
        with pytest.raises(Exception) as error:
            live_deal((client, shop, product), quantity_total=Decimal("20"))
        assert error.value.get_codes() == "insufficient_inventory"

        deal = live_deal((client, shop, product), quantity_total=Decimal("10"))
        _, customer = auth_client()
        reservation = reservations.create_reservation(customer, deal.id, Decimal("2"))
        reservations.confirm(reservation)
        reservations.complete(reservation, reservation.pickup_code)
        assert Inventory.objects.get().quantity_on_hand == Decimal("8")
        low = client.get("/api/v1/inventory/?low_stock=true").data["results"]
        assert [item["product"] for item in low] == [product.id]
