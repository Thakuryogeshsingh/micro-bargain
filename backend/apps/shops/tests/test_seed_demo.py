import pytest
from django.core.management import call_command

from apps.categories.models import Category
from apps.deals.models import Deal
from apps.reviews.models import Review
from apps.shops.demo_data import SHOPS
from apps.shops.models import Shop
from apps.shops.tasks import refresh_demo_deals

PRODUCTS = sum(len(row[-1]) for row in SHOPS)


def demo_shops():
    return Shop.objects.filter(merchant__user__phone__startswith="90000001")


@pytest.mark.django_db
class TestSeedDemo:
    def test_creates_live_deals_near_bharatpur(self, api_client):
        call_command("seed_demo")
        assert demo_shops().filter(status="approved").count() == len(SHOPS)
        response = api_client.get("/api/v1/deals/nearby/", {"latitude": 27.2063, "longitude": 77.4972, "radius": 5000})
        assert response.data["count"] >= 100
        assert all(d["discount_percent"] != "0.00" for d in response.data["results"])

    def test_every_category_has_shops_and_shops_look_real(self):
        call_command("seed_demo")
        assert set(Category.objects.values_list("slug", flat=True)) <= set(demo_shops().values_list("category__slug", flat=True))
        assert not demo_shops().filter(name__contains="(Demo)").exists()
        assert Review.objects.count() > 10

    def test_rerun_adds_no_shops_and_keeps_one_live_deal_per_product(self):
        call_command("seed_demo")
        call_command("seed_demo")
        assert demo_shops().count() == len(SHOPS)
        assert Deal.objects.filter(status=Deal.Status.ACTIVE).count() == PRODUCTS

    def test_expired_deals_are_replaced(self):
        call_command("seed_demo")
        Deal.objects.update(status=Deal.Status.EXPIRED)
        call_command("seed_demo")
        assert Deal.objects.filter(status=Deal.Status.ACTIVE).count() == PRODUCTS

    def test_photos_attached_and_restored_after_disk_wipe(self, api_client, settings):
        import shutil

        from apps.categories.models import Category
        from apps.products.models import ProductImage

        call_command("seed_demo")
        assert ProductImage.objects.filter(product__shop__in=demo_shops()).count() == PRODUCTS
        assert all(s.cover_image for s in demo_shops())
        assert Category.objects.exclude(icon="").count() == 10
        deal = api_client.get("/api/v1/deals/nearby/", {"latitude": 27.2063, "longitude": 77.4972, "radius": 5000}).data["results"][0]
        assert deal["image"]

        shutil.rmtree(settings.MEDIA_ROOT)  # the free server's disk after a restart
        call_command("seed_demo")
        image = ProductImage.objects.filter(product__shop__in=demo_shops()).first().image
        assert image.storage.exists(image.name)
        assert ProductImage.objects.filter(product__shop__in=demo_shops()).count() == PRODUCTS  # restored, not duplicated

    def test_photo_credits_page(self, client):
        body = client.get("/legal/photo-credits/").content.decode()
        assert "Wikimedia Commons" in body and "CC BY" in body

    def test_festival_banner_with_its_own_coupon(self):
        from apps.growth.models import Campaign

        call_command("seed_demo")
        call_command("seed_demo")  # no duplicates
        diwali = Campaign.objects.get(name="Diwali 2026")
        assert diwali.coupon.code == "DIWALI20" and diwali.coupon.value == 20
        assert diwali.coupon.valid_from == diwali.starts_at and diwali.coupon.valid_until == diwali.ends_at
        assert Campaign.objects.count() == 1

    def test_task_only_runs_when_enabled(self, settings):
        settings.SEED_DEMO = False
        refresh_demo_deals()
        assert not Shop.objects.exists()


@pytest.mark.django_db
def test_nearby_shops_show_deal_stats_and_shops_with_deals_first(api_client, merchant_shop):
    call_command("seed_demo")
    merchant_shop(lat=27.2063, lng=77.4972, name="Empty Shop")  # nearest, but no deals
    data = api_client.get("/api/v1/shops/nearby/", {"latitude": 27.2063, "longitude": 77.4972, "radius": 5000, "page_size": 50}).data["results"]
    assert data[0]["live_deals_count"] > 0 and data[0]["max_discount"] is not None
    assert data[-1]["name"] == "Empty Shop" and data[-1]["live_deals_count"] == 0
    detail = api_client.get(f"/api/v1/shops/{data[0]['id']}/").data
    assert detail["live_deals_count"] == data[0]["live_deals_count"]
