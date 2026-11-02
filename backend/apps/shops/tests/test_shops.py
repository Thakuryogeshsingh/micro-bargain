import pytest

from apps.accounts.models import User
from apps.merchants.models import MerchantProfile
from apps.shops.models import Shop
from apps.shops.services import review_shop

# Bharatpur city centre. 0.009° of latitude is roughly 1 km.
LAT, LNG = 27.2152, 77.4890
CREATE = "/api/v1/merchants/shop/create/"
NEARBY = "/api/v1/shops/nearby/"


def shop_payload(category, lat=LAT, lng=LNG, **extra):
    return {
        "name": "Gupta Fruits",
        "category": category.id,
        "address_line": "Mandi Road",
        "city": "Bharatpur",
        "state": "Rajasthan",
        "pincode": "321001",
        "latitude": f"{lat:.6f}",
        "longitude": f"{lng:.6f}",
        **extra,
    }


@pytest.fixture
def merchant_client(auth_client, fruits):
    def _make():
        client, user = auth_client(role=User.Role.MERCHANT)
        MerchantProfile.objects.create(user=user, owner_name="Ramesh", business_category=fruits)
        return client, user

    return _make


@pytest.fixture
def approved_shop(merchant_client, fruits, make_user):
    admin = make_user(role=User.Role.ADMIN)

    def _make(lat=LAT, lng=LNG, name="Gupta Fruits"):
        client, _ = merchant_client()
        shop_id = client.post(CREATE, shop_payload(fruits, lat, lng, name=name)).data["id"]
        return review_shop(Shop.objects.get(pk=shop_id), admin, approve=True)

    return _make


@pytest.mark.django_db
class TestMerchantShops:
    def test_create_shop_is_pending(self, merchant_client, fruits):
        client, _ = merchant_client()
        response = client.post(CREATE, shop_payload(fruits))
        assert response.status_code == 201, response.data
        assert response.data["status"] == "pending"
        assert response.data["latitude"] == pytest.approx(LAT)
        assert response.data["longitude"] == pytest.approx(LNG)

    def test_shop_limit(self, merchant_client, fruits):
        client, _ = merchant_client()
        client.post(CREATE, shop_payload(fruits))
        response = client.post(CREATE, shop_payload(fruits, name="Second"))
        assert response.data["error"]["code"] == "shop_limit"

    def test_customer_cannot_create_shop(self, auth_client, fruits):
        client, _ = auth_client()
        assert client.post(CREATE, shop_payload(fruits)).status_code == 403

    def test_invalid_coordinates(self, merchant_client, fruits):
        client, _ = merchant_client()
        assert client.post(CREATE, shop_payload(fruits, lat=95)).status_code == 400

    def test_update_location(self, merchant_client, fruits):
        client, _ = merchant_client()
        shop_id = client.post(CREATE, shop_payload(fruits)).data["id"]
        response = client.patch(f"/api/v1/merchants/shop/update/{shop_id}/", {"latitude": "27.220000", "longitude": "77.500000"})
        assert response.status_code == 200
        assert response.data["latitude"] == pytest.approx(27.22)

    def test_cannot_update_another_merchants_shop(self, merchant_client, fruits):
        owner, _ = merchant_client()
        shop_id = owner.post(CREATE, shop_payload(fruits)).data["id"]
        other, _ = merchant_client()
        response = other.patch(f"/api/v1/merchants/shop/update/{shop_id}/", {"name": "Hacked"})
        assert response.status_code == 404
        assert Shop.objects.get(pk=shop_id).name == "Gupta Fruits"

    def test_list_only_own_shops(self, merchant_client, fruits):
        owner, _ = merchant_client()
        owner.post(CREATE, shop_payload(fruits))
        other, _ = merchant_client()
        assert other.get("/api/v1/merchants/shop/list/").data == []
        assert len(owner.get("/api/v1/merchants/shop/list/").data) == 1

    def test_approving_shop_approves_pending_merchant(self, approved_shop):
        shop = approved_shop()
        assert shop.status == "approved"
        assert shop.merchant.status == "approved"


@pytest.mark.django_db
class TestNearbyShops:
    def query(self, client, radius=2000, **extra):
        return client.get(NEARBY, {"latitude": LAT, "longitude": LNG, "radius": radius, **extra})

    def test_radius_filtering_and_sorting(self, api_client, approved_shop):
        approved_shop(LAT + 0.017, LNG, name="1.9 km")
        approved_shop(LAT + 0.0045, LNG, name="0.5 km")
        approved_shop(LAT + 0.04, LNG, name="4.4 km")

        results = self.query(api_client, radius=2000).data["results"]
        assert [s["name"] for s in results] == ["0.5 km", "1.9 km"]
        assert 400 < results[0]["distance_m"] < 600

        assert [s["name"] for s in self.query(api_client, radius=1000).data["results"]] == ["0.5 km"]
        assert len(self.query(api_client, radius=5000).data["results"]) == 3

    def test_pending_and_closed_shops_are_hidden(self, api_client, approved_shop, merchant_client, fruits):
        client, _ = merchant_client()
        client.post(CREATE, shop_payload(fruits, name="Pending"))
        closed = approved_shop(name="Closed")
        closed.is_temporarily_closed = True
        closed.save()
        assert self.query(api_client).data["results"] == []

    def test_only_allowed_radius_values(self, api_client):
        assert self.query(api_client, radius=3000).status_code == 400

    def test_missing_or_bad_coordinates(self, api_client):
        assert api_client.get(NEARBY).status_code == 400
        assert api_client.get(NEARBY, {"latitude": 200, "longitude": LNG}).status_code == 400

    def test_shops_at_same_coordinates(self, api_client, approved_shop):
        approved_shop(name="A")
        approved_shop(name="B")
        assert len(self.query(api_client).data["results"]) == 2


@pytest.mark.django_db
class TestFavorites:
    def test_add_list_remove(self, auth_client, approved_shop):
        shop = approved_shop()
        client, _ = auth_client()
        assert client.post(f"/api/v1/shops/{shop.id}/favorite/").status_code == 201
        assert client.post(f"/api/v1/shops/{shop.id}/favorite/").status_code == 201  # idempotent
        favorites = client.get("/api/v1/shops/favorites/").data["results"]
        assert [s["id"] for s in favorites] == [shop.id]
        assert favorites[0]["is_favorite"] is True
        assert client.delete(f"/api/v1/shops/{shop.id}/favorite/").status_code == 204
        assert client.get("/api/v1/shops/favorites/").data["results"] == []

    def test_cannot_favorite_pending_shop(self, auth_client, merchant_client, fruits):
        owner, _ = merchant_client()
        shop_id = owner.post(CREATE, shop_payload(fruits)).data["id"]
        client, _ = auth_client()
        assert client.post(f"/api/v1/shops/{shop_id}/favorite/").status_code == 404
