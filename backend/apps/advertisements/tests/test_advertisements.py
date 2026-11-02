import io
from datetime import timedelta

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from PIL import Image

from apps.advertisements import services
from apps.advertisements.models import Advertisement
from apps.payments import gateway
from apps.payments.models import Refund
from conftest import BHARATPUR

NEARBY = "/api/v1/deals/nearby/"


def pay_ad(client, ad_id):
    checkout = client.post("/api/v1/payments/create/", {"purpose": "advertisement", "id": ad_id}).data
    client.post("/api/v1/payments/verify/", {
        "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": "pay_ad",
        "razorpay_signature": gateway.checkout_signature(checkout["razorpay_order_id"], "pay_ad"),
    })
    return checkout


def png():
    buffer = io.BytesIO()
    Image.new("RGB", (20, 10), "orange").save(buffer, format="PNG")
    return SimpleUploadedFile("banner.png", buffer.getvalue(), content_type="image/png")


@pytest.mark.django_db
class TestFeaturedDeals:
    def test_featured_deal_shows_first(self, live_deal, merchant_shop, api_client):
        near = live_deal()
        # 1 km away: normally second.
        far = live_deal(merchant_shop(lat=BHARATPUR[0] + 0.009, lng=BHARATPUR[1]))
        ad = far.merchant_client.post("/api/v1/advertisements/create/", {"placement": "featured_deal", "deal": far.id, "days": 3}).data
        assert ad["price"] == "147.00" and ad["status"] == "pending_payment"

        params = {"latitude": BHARATPUR[0], "longitude": BHARATPUR[1]}
        assert [d["id"] for d in api_client.get(NEARBY, params).data["results"]] == [near.id, far.id]
        assert pay_ad(far.merchant_client, ad["id"])["amount"] == 14700
        results = api_client.get(NEARBY, params).data["results"]
        assert [(d["id"], d["is_featured"]) for d in results] == [(far.id, True), (near.id, False)]

    def test_cannot_feature_other_shops_deal(self, live_deal):
        mine, theirs = live_deal(), live_deal()
        response = mine.merchant_client.post("/api/v1/advertisements/create/", {"placement": "featured_deal", "deal": theirs.id, "days": 1})
        assert response.data["error"]["code"] == "invalid_deal"


@pytest.mark.django_db
class TestBanners:
    def test_banner_reach_and_counters(self, merchant_shop, api_client):
        client, shop, _ = merchant_shop()
        ad = client.post("/api/v1/advertisements/create/", {
            "placement": "home_banner", "days": 1, "title": "Diwali sale", "banner_image": png(), "radius_m": 1000,
        }, format="multipart").data
        pay_ad(client, ad["id"])

        close = api_client.get("/api/v1/advertisements/banners/", {"latitude": BHARATPUR[0], "longitude": BHARATPUR[1]}).data
        assert [b["title"] for b in close] == ["Diwali sale"]
        far = api_client.get("/api/v1/advertisements/banners/", {"latitude": BHARATPUR[0] + 0.03, "longitude": BHARATPUR[1]}).data
        assert far == []
        api_client.post(f"/api/v1/advertisements/{ad['id']}/click/")
        ad = Advertisement.objects.get()
        assert (ad.impressions, ad.clicks) == (1, 1)

    def test_admin_reject_refunds(self, merchant_shop, make_user, django_capture_on_commit_callbacks):
        client, _, _ = merchant_shop()
        ad = client.post("/api/v1/advertisements/create/", {
            "placement": "home_banner", "days": 2, "title": "Sale", "banner_image": png(),
        }, format="multipart").data
        pay_ad(client, ad["id"])
        with django_capture_on_commit_callbacks(execute=True):
            services.reject(Advertisement.objects.get(), make_user(role="admin"), "Misleading")
        assert Refund.objects.get().amount == 198 and Advertisement.objects.get().status == "rejected"

    def test_expiry(self, merchant_shop):
        client, _, _ = merchant_shop()
        ad = client.post("/api/v1/advertisements/create/", {"placement": "home_banner", "days": 1, "title": "x", "banner_image": png()}, format="multipart").data
        pay_ad(client, ad["id"])
        Advertisement.objects.update(ends_at=timezone.now() - timedelta(seconds=1))
        assert services.expire_ads() == 1
