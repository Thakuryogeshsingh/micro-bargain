import pytest
from django.core.cache import cache
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.categories.models import Category


@pytest.fixture(autouse=True)
def _clear_cache():
    # Throttle counters live in the cache; keep tests independent.
    cache.clear()
    yield
    cache.clear()


@pytest.fixture(autouse=True)
def _celery_eager():
    # Run Celery tasks inline so tests never need Redis.
    from config.celery import app

    app.conf.task_always_eager = True
    yield


@pytest.fixture(autouse=True)
def _media_in_tmp(settings, tmp_path):
    # Uploaded files (reviews, complaints, demo photos) go to a throwaway folder, not backend/media.
    settings.MEDIA_ROOT = tmp_path / "media"


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def make_user(db):
    counter = iter(range(1000, 9999))

    def _make(role=User.Role.CUSTOMER, **kwargs):
        phone = kwargs.pop("phone", f"98765{next(counter):05d}")
        return User.objects.create_user(phone=phone, role=role, is_phone_verified=True, **kwargs)

    return _make


@pytest.fixture
def auth_client(make_user):
    """auth_client(role) -> (client logged in as a new user, user)."""

    def _client(role=User.Role.CUSTOMER, **kwargs):
        user = make_user(role=role, **kwargs)
        client = APIClient()
        client.force_authenticate(user=user)
        return client, user

    return _client


@pytest.fixture
def fruits(db):
    return Category.objects.get(slug="fruits")


# Bharatpur city centre. 0.009° of latitude is roughly 1 km.
BHARATPUR = (27.2152, 77.4890)


@pytest.fixture
def merchant_shop(make_user, fruits):
    """merchant_shop(lat, lng, approved=True) -> (logged-in merchant client, shop, product)."""
    from apps.merchants.models import MerchantProfile
    from apps.products.models import Product
    from apps.shops.models import Shop
    from apps.shops.services import make_point

    def _make(lat=BHARATPUR[0], lng=BHARATPUR[1], approved=True, product_name="सेब (शिमला)", **shop_fields):
        user = make_user(role=User.Role.MERCHANT)
        status = "approved" if approved else "pending"
        merchant = MerchantProfile.objects.create(user=user, owner_name="Ramesh", business_category=fruits, status=status)
        shop = Shop.objects.create(
            merchant=merchant, name=shop_fields.pop("name", "Gupta Fruits"), category=fruits,
            address_line="Mandi Road", city="Bharatpur", state="Rajasthan", pincode="321001",
            location=make_point(lat, lng), status=status, **shop_fields,
        )
        product = Product.objects.create(shop=shop, category=fruits, name=product_name, unit="kg", standard_price=100)
        client = APIClient()
        client.force_authenticate(user=user)
        return client, shop, product

    return _make


@pytest.fixture
def live_deal(merchant_shop):
    """live_deal(**deal_fields) -> a published deal (₹60 instead of ₹100, 20 kg) with .merchant_client attached."""
    from decimal import Decimal

    from apps.deals import services as deal_services

    def _make(shop_and_product=None, **fields):
        client, shop, product = shop_and_product or merchant_shop()
        values = dict(normal_price=Decimal("100"), offer_price=Decimal("60"), quantity_total=Decimal("20"),
                      duration_minutes=120, publish=True)
        values.update(fields)
        deal = deal_services.create_deal(shop.merchant.user, shop=shop, product=product, **values)
        deal.merchant_client = client
        return deal

    return _make
