import pytest
from django.core.management import call_command

from apps.deals.models import Deal
from apps.shops.models import Shop
from apps.shops.tasks import refresh_demo_deals


@pytest.mark.django_db
class TestSeedDemo:
    def test_creates_live_deals_near_bharatpur(self, api_client):
        call_command("seed_demo")
        assert Shop.objects.filter(name__endswith="(Demo)", status="approved").count() == 6
        response = api_client.get("/api/v1/deals/nearby/", {"latitude": 27.2063, "longitude": 77.4972, "radius": 5000})
        assert response.data["count"] == 22
        assert all(d["discount_percent"] != "0.00" for d in response.data["results"])

    def test_rerun_adds_nothing_while_deals_are_live(self):
        call_command("seed_demo")
        call_command("seed_demo")
        assert Shop.objects.count() == 6 and Deal.objects.count() == 22

    def test_expired_deals_are_replaced(self):
        call_command("seed_demo")
        Deal.objects.update(status=Deal.Status.EXPIRED)
        call_command("seed_demo")
        assert Deal.objects.filter(status=Deal.Status.ACTIVE).count() == 22

    def test_task_only_runs_when_enabled(self, settings):
        settings.SEED_DEMO = False
        refresh_demo_deals()
        assert not Shop.objects.exists()
