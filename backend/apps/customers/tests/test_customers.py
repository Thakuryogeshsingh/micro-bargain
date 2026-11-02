import pytest

from apps.accounts.models import User

ADDRESSES = "/api/v1/customers/addresses/"
ADDRESS = {
    "label": "Home",
    "address_line": "12, Ranjit Nagar",
    "city": "Bharatpur",
    "state": "Rajasthan",
    "pincode": "321001",
    "latitude": "27.215000",
    "longitude": "77.490000",
}


@pytest.mark.django_db
class TestCustomerProfile:
    def test_defaults_to_2km(self, auth_client):
        client, _ = auth_client()
        response = client.get("/api/v1/customers/profile/")
        assert response.status_code == 200
        assert response.data["search_radius_m"] == 2000

    def test_update_radius_and_preferences(self, auth_client, fruits):
        client, _ = auth_client()
        response = client.patch(
            "/api/v1/customers/profile/",
            {"search_radius_m": 5000, "notify_nearby_deals": False, "preferred_categories": [fruits.id]},
            format="json",
        )
        assert response.status_code == 200
        assert response.data["search_radius_m"] == 5000
        assert response.data["preferred_categories"] == [fruits.id]

    def test_radius_must_be_an_allowed_value(self, auth_client):
        client, _ = auth_client()
        response = client.patch("/api/v1/customers/profile/", {"search_radius_m": 3000})
        assert response.status_code == 400

    def test_merchants_cannot_use_customer_profile(self, auth_client):
        client, _ = auth_client(role=User.Role.MERCHANT)
        assert client.get("/api/v1/customers/profile/").status_code == 403


@pytest.mark.django_db
class TestAddresses:
    def test_first_address_becomes_default(self, auth_client):
        client, _ = auth_client()
        response = client.post(ADDRESSES, ADDRESS)
        assert response.status_code == 201
        assert response.data["is_default"] is True

    def test_only_one_default(self, auth_client):
        client, user = auth_client()
        client.post(ADDRESSES, ADDRESS)
        client.post(ADDRESSES, {**ADDRESS, "label": "Shop", "is_default": True})
        assert user.addresses.filter(is_default=True).count() == 1
        assert user.addresses.get(is_default=True).label == "Shop"

    def test_invalid_coordinates(self, auth_client):
        client, _ = auth_client()
        response = client.post(ADDRESSES, {**ADDRESS, "latitude": "120.000000"})
        assert response.status_code == 400

    def test_invalid_pincode(self, auth_client):
        client, _ = auth_client()
        response = client.post(ADDRESSES, {**ADDRESS, "pincode": "012345"})
        assert response.status_code == 400

    def test_cannot_see_or_edit_others_addresses(self, auth_client):
        owner, _ = auth_client()
        address_id = owner.post(ADDRESSES, ADDRESS).data["id"]
        other, _ = auth_client()
        assert other.get(f"{ADDRESSES}{address_id}/").status_code == 404
        assert other.delete(f"{ADDRESSES}{address_id}/").status_code == 404
        assert other.get(ADDRESSES).data == []

    def test_address_limit(self, auth_client, settings):
        settings.MAX_ADDRESSES_PER_CUSTOMER = 2
        client, _ = auth_client()
        client.post(ADDRESSES, ADDRESS)
        client.post(ADDRESSES, ADDRESS)
        response = client.post(ADDRESSES, ADDRESS)
        assert response.data["error"]["code"] == "address_limit"
