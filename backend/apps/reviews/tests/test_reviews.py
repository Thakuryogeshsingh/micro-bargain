from decimal import Decimal

import pytest

from apps.commissions.models import Commission
from apps.reservations import services as reservations
from apps.reviews import services
from apps.reviews.models import Review

CREATE = "/api/v1/reviews/create/"


@pytest.fixture
def completed(auth_client, live_deal):
    """A customer client and a reservation they have picked up."""
    client, customer = auth_client(name="Sunita Sharma")
    reservation = reservations.create_reservation(customer, live_deal().id, Decimal("2"))
    reservations.confirm(reservation)
    return client, reservations.complete(reservation, reservation.pickup_code)


@pytest.mark.django_db
class TestReviews:
    def test_review_updates_shop_rating(self, completed, auth_client, live_deal):
        client, reservation = completed
        response = client.post(CREATE, {"reservation": reservation.id, "rating": 4, "comment": "Taaza seb"})
        assert response.status_code == 201, response.data
        assert response.data["customer_name"] == "Sunita"  # first name only
        shop = reservation.shop
        shop.refresh_from_db()
        assert (shop.rating_avg, shop.rating_count) == (Decimal("4.00"), 1)
        assert shop.merchant.user.notifications.filter(kind="new_review").exists()

    def test_once_per_purchase(self, completed):
        client, reservation = completed
        client.post(CREATE, {"reservation": reservation.id, "rating": 5})
        assert client.post(CREATE, {"reservation": reservation.id, "rating": 1}).data["error"]["code"] == "already_reviewed"

    def test_only_after_pickup(self, auth_client, live_deal):
        client, customer = auth_client()
        reservation = reservations.create_reservation(customer, live_deal().id, Decimal("1"))
        assert client.post(CREATE, {"reservation": reservation.id, "rating": 5}).data["error"]["code"] == "not_completed"

    def test_cannot_review_others_purchase(self, completed, auth_client):
        _, reservation = completed
        stranger, _ = auth_client()
        assert stranger.post(CREATE, {"reservation": reservation.id, "rating": 1}).status_code == 404

    def test_public_list_reply_and_hide(self, completed, api_client, make_user):
        client, reservation = completed
        review_id = client.post(CREATE, {"reservation": reservation.id, "rating": 2}).data["id"]
        merchant = reservation.shop.merchant.user
        from rest_framework.test import APIClient

        merchant_client = APIClient()
        merchant_client.force_authenticate(merchant)
        assert merchant_client.post(f"/api/v1/reviews/{review_id}/reply/", {"reply": "Maaf kijiye"}).data["merchant_reply"] == "Maaf kijiye"
        assert api_client.get(f"/api/v1/reviews/shop/{reservation.shop_id}/").data["count"] == 1

        services.set_hidden(Review.objects.get(), True, make_user(role="admin"))
        assert api_client.get(f"/api/v1/reviews/shop/{reservation.shop_id}/").data["count"] == 0
        reservation.shop.refresh_from_db()
        assert reservation.shop.rating_count == 0

    def test_pickup_records_commission(self, completed):
        _, reservation = completed
        assert Commission.objects.get().amount == Decimal("3.60")  # 3% of ₹120
