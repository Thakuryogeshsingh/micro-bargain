import pytest
from django.core.management import call_command

from apps.categories.models import Category
from apps.deals.models import Deal
from apps.reviews.models import Review
from apps.shops.demo_data import SHOPS
from apps.shops.models import Shop


@pytest.mark.django_db
def test_seed_demo_fills_every_category_and_is_repeatable():
    call_command("seed_demo")
    shops = Shop.objects.filter(merchant__user__phone__startswith="90000001")
    assert shops.count() == len(SHOPS)
    assert set(Category.objects.values_list("slug", flat=True)) <= set(shops.values_list("category__slug", flat=True))
    assert Deal.objects.filter(status="active").count() >= 150
    assert Review.objects.count() > 10
    assert not shops.filter(name__contains="(Demo)").exists()

    call_command("seed_demo")  # hourly refresh: no duplicates
    assert Shop.objects.filter(merchant__user__phone__startswith="90000001").count() == len(SHOPS)
