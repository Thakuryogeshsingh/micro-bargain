from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.deals.models import Deal


@pytest.mark.django_db
class TestRepeatYesterday:
    def test_republishes_yesterdays_deals(self, live_deal):
        deal = live_deal()
        yesterday = timezone.now() - timedelta(days=1)
        Deal.objects.filter(pk=deal.pk).update(published_at=yesterday, status="expired", expires_at=timezone.now() - timedelta(hours=1),
                                               starts_at=yesterday)
        response = deal.merchant_client.post("/api/v1/deals/repeat-yesterday/")
        assert response.data == {"created": 1, "skipped": 0}
        fresh = Deal.objects.exclude(pk=deal.pk).get()
        assert fresh.status == "active" and fresh.offer_price == deal.offer_price

    def test_skips_products_already_live(self, live_deal):
        deal = live_deal()
        Deal.objects.filter(pk=deal.pk).update(published_at=timezone.now() - timedelta(days=1))
        assert deal.merchant_client.post("/api/v1/deals/repeat-yesterday/").data == {"created": 0, "skipped": 1}


@pytest.mark.django_db
class TestPriceSuggestion:
    def test_uses_smallest_discount_that_sold_well(self, live_deal, merchant_shop):
        client, shop, product = merchant_shop()
        well = live_deal((client, shop, product), offer_price=Decimal("75"))  # 25% off
        Deal.objects.filter(pk=well.pk).update(quantity_sold=Decimal("18"), status="expired")
        data = client.get("/api/v1/deals/price-suggestion/", {"product": product.id}).data
        assert data["discount_percent"] == Decimal("25") and data["offer_price"] == Decimal("75") and data["reason"] == "past"

    def test_default_without_history(self, merchant_shop):
        client, _, product = merchant_shop()
        data = client.get("/api/v1/deals/price-suggestion/", {"product": product.id}).data
        assert data["reason"] == "default" and data["offer_price"] == Decimal("70")

    def test_other_merchants_product_404(self, merchant_shop):
        client, _, _ = merchant_shop()
        _, _, other = merchant_shop()
        assert client.get("/api/v1/deals/price-suggestion/", {"product": other.id}).status_code == 404


@pytest.mark.django_db
def test_share_page(live_deal, client):
    deal = live_deal()
    response = client.get(f"/d/{deal.id}/")
    assert response.status_code == 200 and "microbargain://deal/" in response.content.decode()
