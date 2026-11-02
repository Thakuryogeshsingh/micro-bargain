import io

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from PIL import Image

from apps.accounts.models import User
from apps.merchants.models import MerchantProfile
from apps.shops.models import Shop
from apps.shops.services import make_point


def png_file(name="apple.png"):
    buffer = io.BytesIO()
    Image.new("RGB", (10, 10), "red").save(buffer, "PNG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/png")


@pytest.fixture
def merchant_with_shop(auth_client, fruits):
    def _make():
        client, user = auth_client(role=User.Role.MERCHANT)
        merchant = MerchantProfile.objects.create(user=user, owner_name="Ramesh", business_category=fruits)
        shop = Shop.objects.create(
            merchant=merchant, name="Gupta Fruits", category=fruits, address_line="Mandi Road",
            city="Bharatpur", state="Rajasthan", pincode="321001", location=make_point(27.2152, 77.4890),
        )
        return client, shop

    return _make


def product_payload(shop, category, **extra):
    return {"shop": shop.id, "category": category.id, "name": "सेब (शिमला)", "unit": "kg", "standard_price": "100.00", **extra}


@pytest.mark.django_db
class TestProducts:
    def test_create_and_list(self, merchant_with_shop, fruits):
        client, shop = merchant_with_shop()
        response = client.post("/api/v1/products/create/", product_payload(shop, fruits))
        assert response.status_code == 201, response.data
        listing = client.get("/api/v1/products/").data["results"]
        assert [p["name"] for p in listing] == ["सेब (शिमला)"]

    def test_cannot_add_to_another_merchants_shop(self, merchant_with_shop, fruits):
        _, other_shop = merchant_with_shop()
        client, _ = merchant_with_shop()
        response = client.post("/api/v1/products/create/", product_payload(other_shop, fruits))
        assert response.status_code == 400

    @pytest.mark.parametrize("price", ["0", "-5"])
    def test_price_must_be_positive(self, merchant_with_shop, fruits, price):
        client, shop = merchant_with_shop()
        response = client.post("/api/v1/products/create/", product_payload(shop, fruits, standard_price=price))
        assert response.status_code == 400

    def test_invalid_unit(self, merchant_with_shop, fruits):
        client, shop = merchant_with_shop()
        response = client.post("/api/v1/products/create/", product_payload(shop, fruits, unit="ton"))
        assert response.status_code == 400

    def test_update_and_ownership(self, merchant_with_shop, fruits):
        client, shop = merchant_with_shop()
        product_id = client.post("/api/v1/products/create/", product_payload(shop, fruits)).data["id"]
        response = client.patch(f"/api/v1/products/update/{product_id}/", {"standard_price": "120.00"})
        assert response.data["standard_price"] == "120.00"

        other, _ = merchant_with_shop()
        assert other.patch(f"/api/v1/products/update/{product_id}/", {"name": "x"}).status_code == 404
        assert other.delete(f"/api/v1/products/delete/{product_id}/").status_code == 404

    def test_delete(self, merchant_with_shop, fruits):
        client, shop = merchant_with_shop()
        product_id = client.post("/api/v1/products/create/", product_payload(shop, fruits)).data["id"]
        assert client.delete(f"/api/v1/products/delete/{product_id}/").status_code == 204

    def test_image_upload_and_limit(self, merchant_with_shop, fruits, settings, tmp_path):
        settings.MEDIA_ROOT = tmp_path
        settings.MAX_IMAGES_PER_PRODUCT = 1
        client, shop = merchant_with_shop()
        product_id = client.post("/api/v1/products/create/", product_payload(shop, fruits)).data["id"]
        response = client.post("/api/v1/products/upload-image/", {"product": product_id, "image": png_file()}, format="multipart")
        assert response.status_code == 201, response.data
        response = client.post("/api/v1/products/upload-image/", {"product": product_id, "image": png_file()}, format="multipart")
        assert response.data["error"]["code"] == "image_limit"

    def test_rejects_non_image(self, merchant_with_shop, fruits):
        client, shop = merchant_with_shop()
        product_id = client.post("/api/v1/products/create/", product_payload(shop, fruits)).data["id"]
        fake = SimpleUploadedFile("x.png", b"not an image", content_type="image/png")
        response = client.post("/api/v1/products/upload-image/", {"product": product_id, "image": fake}, format="multipart")
        assert response.status_code == 400

    def test_customer_cannot_manage_products(self, auth_client):
        client, _ = auth_client()
        assert client.get("/api/v1/products/").status_code == 403
