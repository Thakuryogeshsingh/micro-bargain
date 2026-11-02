from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.deals import services as deal_services
from apps.deals.models import Deal
from apps.reservations import services
from apps.reservations.models import DealReservation

CREATE = "/api/v1/reservations/create/"


@pytest.fixture
def deal(merchant_shop):
    """A live deal: ₹60/kg instead of ₹100, 20 kg."""
    client, shop, product = merchant_shop()
    deal = deal_services.create_deal(
        shop.merchant.user, shop=shop, product=product, normal_price=Decimal("100"), offer_price=Decimal("60"),
        quantity_total=Decimal("20"), duration_minutes=120, publish=True,
    )
    deal.merchant_client = client
    return deal


def reserve(client, deal, quantity="2"):
    return client.post(CREATE, {"deal": deal.id, "quantity": quantity})


def stock(deal):
    deal.refresh_from_db()
    return deal.quantity_reserved, deal.quantity_sold, deal.status


@pytest.mark.django_db
class TestCustomerReservation:
    def test_reserve_holds_stock(self, auth_client, deal):
        client, _ = auth_client()
        response = reserve(client, deal)
        assert response.status_code == 201, response.data
        data = response.data
        assert data["reservation_number"].startswith("MB-")
        assert data["status"] == "pending"
        assert data["total_amount"] == "120.00" and data["savings"] == "80.00"
        assert len(data["pickup_code"]) == 4
        assert stock(deal) == (2, 0, "active")

    def test_cannot_reserve_more_than_available(self, auth_client, deal):
        client, _ = auth_client()
        response = reserve(client, deal, "25")
        assert response.data["error"]["code"] == "insufficient_stock"
        assert stock(deal) == (0, 0, "active")

    def test_double_tap_creates_one_reservation(self, auth_client, deal):
        client, _ = auth_client()
        reserve(client, deal)
        assert reserve(client, deal).data["error"]["code"] == "already_reserved"
        assert DealReservation.objects.count() == 1
        assert stock(deal) == (2, 0, "active")

    def test_open_reservation_limit(self, auth_client, merchant_shop, settings):
        settings.MAX_ACTIVE_RESERVATIONS_PER_CUSTOMER = 1
        client, _ = auth_client()
        deals = []
        for _ in range(2):
            _, shop, product = merchant_shop()
            deals.append(deal_services.create_deal(
                shop.merchant.user, shop=shop, product=product, offer_price=Decimal("50"),
                quantity_total=Decimal("5"), duration_minutes=60, publish=True))
        reserve(client, deals[0])
        assert reserve(client, deals[1]).data["error"]["code"] == "reservation_limit"

    def test_paused_deal_cannot_be_reserved(self, auth_client, deal):
        deal_services.change_status(deal, None, Deal.Status.PAUSED)
        client, _ = auth_client()
        assert reserve(client, deal).data["error"]["code"] == "deal_unavailable"

    def test_last_stock_marks_deal_sold_out(self, auth_client, deal):
        client, _ = auth_client()
        reserve(client, deal, "20")
        assert stock(deal) == (20, 0, "sold_out")

    def test_cancel_releases_stock(self, auth_client, deal):
        client, _ = auth_client()
        reservation_id = reserve(client, deal, "20").data["id"]
        response = client.post(f"/api/v1/reservations/{reservation_id}/cancel/", {"reason": "Plans changed"})
        assert response.data["status"] == "cancelled"
        assert stock(deal) == (0, 0, "active")
        # Cancelled reservations do not block reserving again.
        assert reserve(client, deal).status_code == 201

    def test_merchant_cannot_reserve(self, deal):
        assert reserve(deal.merchant_client, deal).status_code == 403

    def test_customers_only_see_their_own(self, auth_client, deal):
        owner, _ = auth_client()
        reservation_id = reserve(owner, deal).data["id"]
        other, _ = auth_client()
        assert other.get(f"/api/v1/reservations/{reservation_id}/").status_code == 404
        assert other.post(f"/api/v1/reservations/{reservation_id}/cancel/").status_code == 404
        assert other.get("/api/v1/reservations/").data["count"] == 0
        assert owner.get("/api/v1/reservations/").data["count"] == 1


@pytest.mark.django_db
class TestMerchantHandling:
    def test_confirm_then_complete_with_code(self, auth_client, deal):
        client, _ = auth_client()
        created = reserve(client, deal).data
        merchant = deal.merchant_client
        base = f"/api/v1/reservations/{created['id']}"

        listing = merchant.get("/api/v1/reservations/").data["results"][0]
        assert "pickup_code" not in listing
        assert listing["customer_phone"].endswith("xxxxx")

        assert merchant.post(f"{base}/confirm/").data["status"] == "confirmed"
        wrong = "0000" if created["pickup_code"] != "0000" else "1111"
        assert merchant.post(f"{base}/complete/", {"pickup_code": wrong}).data["error"]["code"] == "wrong_pickup_code"
        response = merchant.post(f"{base}/complete/", {"pickup_code": created["pickup_code"]})
        assert response.data["status"] == "completed"
        assert stock(deal) == (0, 2, "active")

        stats = merchant.get("/api/v1/merchants/dashboard/").data
        assert stats["completed_orders"] == 1 and stats["revenue"] == Decimal("120")

    def test_cannot_complete_without_confirming(self, auth_client, deal):
        client, _ = auth_client()
        created = reserve(client, deal).data
        response = deal.merchant_client.post(
            f"/api/v1/reservations/{created['id']}/complete/", {"pickup_code": created["pickup_code"]})
        assert response.data["error"]["code"] == "invalid_status"

    def test_reject_releases_stock(self, auth_client, deal):
        client, _ = auth_client()
        reservation_id = reserve(client, deal, "5").data["id"]
        response = deal.merchant_client.post(f"/api/v1/reservations/{reservation_id}/reject/", {"reason": "Stock damaged"})
        assert response.data["status"] == "rejected" and response.data["closed_reason"] == "Stock damaged"
        assert stock(deal) == (0, 0, "active")

    def test_other_shop_cannot_touch_it(self, auth_client, deal, merchant_shop):
        client, _ = auth_client()
        reservation_id = reserve(client, deal).data["id"]
        other_merchant, _, _ = merchant_shop(name="Other")
        assert other_merchant.post(f"/api/v1/reservations/{reservation_id}/confirm/").status_code == 404

    def test_customer_cannot_confirm_own(self, auth_client, deal):
        client, _ = auth_client()
        reservation_id = reserve(client, deal).data["id"]
        assert client.post(f"/api/v1/reservations/{reservation_id}/confirm/").status_code == 403


@pytest.mark.django_db
class TestExpiry:
    def test_unclaimed_reservations_expire_and_release_stock(self, auth_client, deal):
        client, user = auth_client()
        reserve(client, deal, "20")
        assert stock(deal) == (20, 0, "sold_out")
        DealReservation.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        assert services.expire_reservations() == 1
        assert DealReservation.objects.get().status == "expired"
        assert stock(deal) == (0, 0, "active")
        assert services.expire_reservations() == 0  # idempotent

    def test_completed_reservations_are_not_expired(self, auth_client, deal):
        client, _ = auth_client()
        created = reserve(client, deal).data
        reservation = DealReservation.objects.get(pk=created["id"])
        services.confirm(reservation)
        services.complete(reservation, created["pickup_code"])
        DealReservation.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        assert services.expire_reservations() == 0
        assert stock(deal) == (0, 2, "active")
