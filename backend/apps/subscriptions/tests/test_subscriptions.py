from datetime import timedelta

import pytest
from django.utils import timezone

from apps.payments import gateway
from apps.subscriptions import services
from apps.subscriptions.models import MerchantSubscription


def buy(client, plan="basic", months=1):
    subscription = client.post("/api/v1/subscriptions/subscribe/", {"plan": plan, "months": months}).data
    checkout = client.post("/api/v1/payments/create/", {"purpose": "subscription", "id": subscription["id"]}).data
    response = client.post("/api/v1/payments/verify/", {
        "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": "pay_sub",
        "razorpay_signature": gateway.checkout_signature(checkout["razorpay_order_id"], "pay_sub"),
    })
    assert response.status_code == 200, response.data
    return subscription, checkout


@pytest.mark.django_db
class TestPlans:
    def test_seeded_plans_are_public(self, api_client):
        plans = api_client.get("/api/v1/subscriptions/plans/").data
        assert [(p["code"], p["price_monthly"]) for p in plans] == [("free", "0.00"), ("basic", "199.00"), ("premium", "499.00")]

    def test_free_plan_limits_live_deals(self, live_deal, merchant_shop):
        shop_and_product = merchant_shop()
        for _ in range(3):
            live_deal(shop_and_product)
        with pytest.raises(Exception) as error:
            live_deal(shop_and_product)
        assert error.value.get_codes() == "plan_deal_limit"

    def test_buy_basic_plan(self, merchant_shop):
        client, shop, _ = merchant_shop()
        subscription, checkout = buy(client, "basic", months=2)
        assert checkout["amount"] == 39800  # paise
        current = client.get("/api/v1/subscriptions/current/").data
        assert current["plan"]["code"] == "basic"
        ends = MerchantSubscription.objects.get().ends_at
        assert timedelta(days=59) < ends - timezone.now() <= timedelta(days=60)
        assert shop.merchant.user.notifications.filter(kind="subscription_active").exists()

    def test_renewal_starts_after_current_period(self, merchant_shop):
        client, shop, _ = merchant_shop()
        buy(client)
        buy(client)
        first, second = MerchantSubscription.objects.order_by("id")
        assert second.starts_at == first.ends_at

    def test_free_plan_cannot_be_bought(self, merchant_shop):
        client, _, _ = merchant_shop()
        assert client.post("/api/v1/subscriptions/subscribe/", {"plan": "free"}).data["error"]["code"] == "invalid_plan"

    def test_expiry(self, merchant_shop):
        client, shop, _ = merchant_shop()
        buy(client)
        MerchantSubscription.objects.update(ends_at=timezone.now() - timedelta(seconds=1))
        assert services.expire_subscriptions() == 1
        assert services.current_plan(shop.merchant).code == "free"
