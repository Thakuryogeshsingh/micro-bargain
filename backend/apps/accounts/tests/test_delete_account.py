from decimal import Decimal

import pytest

from apps.accounts.models import User
from apps.customers.models import Address
from apps.reservations import services as reservations

URL = "/api/v1/auth/delete-account/"


@pytest.mark.django_db
class TestDeleteAccount:
    def test_customer_is_anonymised_and_logged_out(self, auth_client, live_deal):
        client, user = auth_client(name="Sunita Sharma")
        phone = user.phone
        Address.objects.create(user=user, address_line="x", city="Bharatpur", state="Rajasthan", pincode="321001",
                               latitude=27.2, longitude=77.4)
        reservation = reservations.create_reservation(user, live_deal().id, Decimal("1"))
        reservations.cancel(reservation)

        assert client.post(URL).status_code == 204
        user.refresh_from_db()
        assert user.phone != phone and user.name == "" and not user.is_active
        assert not user.addresses.exists()
        assert user.reservations.count() == 1  # kept for records
        assert not User.objects.filter(phone=phone).exists()  # number can sign up again

    def test_blocked_while_reservation_open(self, auth_client, live_deal):
        client, user = auth_client()
        reservations.create_reservation(user, live_deal().id, Decimal("1"))
        assert client.post(URL).data["error"]["code"] == "open_bookings"

    def test_merchant_shop_closes_and_deals_end(self, live_deal):
        deal = live_deal()
        assert deal.merchant_client.post(URL).status_code == 204
        deal.refresh_from_db()
        deal.shop.refresh_from_db()
        assert deal.status == "ended" and deal.shop.is_temporarily_closed


@pytest.mark.django_db
@pytest.mark.parametrize("page", ["privacy", "terms", "refunds"])
def test_legal_pages(client, page):
    response = client.get(f"/legal/{page}/")
    assert response.status_code == 200 and b"Micro Bargain" in response.content


@pytest.mark.django_db
def test_unknown_legal_page(client):
    assert client.get("/legal/other/").status_code == 404
