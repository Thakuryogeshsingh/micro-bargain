from datetime import timedelta
from decimal import Decimal

import pytest
from django.utils import timezone

from apps.commissions.models import Commission
from apps.customers.models import Address
from apps.orders import services
from apps.orders.models import Coupon, Order
from apps.payments import gateway
from apps.payments.models import Payment, Refund
from apps.products.models import Product

CREATE = "/api/v1/orders/create/"


def stock(deal):
    deal.refresh_from_db()
    return deal.quantity_reserved, deal.quantity_sold


def order_body(*lines, **extra):
    return {"items": [{"deal": d.id, "quantity": q} for d, q in lines], "payment_method": "cash", **extra}


def pay(client, order):
    """Run the full app-side payment: create -> (Razorpay Checkout) -> verify."""
    checkout = client.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]}, format="json").data
    payment_id = "pay_test123"
    return client.post("/api/v1/payments/verify/", {
        "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": payment_id,
        "razorpay_signature": gateway.checkout_signature(checkout["razorpay_order_id"], payment_id),
    }, format="json")


@pytest.mark.django_db
class TestCreateOrder:
    def test_cash_pickup_order_holds_stock(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        response = client.post(CREATE, order_body((deal, "2")), format="json")
        assert response.status_code == 201, response.data
        data = response.data
        assert data["status"] == "pending" and data["order_number"].startswith("OD-")
        assert data["subtotal"] == "120.00" and data["savings"] == "80.00" and data["total_amount"] == "120.00"
        assert stock(deal) == (2, 0)
        assert deal.shop.merchant.user.notifications.get().kind == "new_order"

    def test_multi_item_same_shop(self, auth_client, live_deal, merchant_shop, fruits):
        client, _ = auth_client()
        first = live_deal()
        shop = first.shop
        banana = Product.objects.create(shop=shop, category=fruits, name="केला", unit="dozen", standard_price=60)
        second = live_deal((first.merchant_client, shop, banana), normal_price=Decimal("60"), offer_price=Decimal("45"))
        response = client.post(CREATE, order_body((first, "1"), (second, "2")), format="json")
        assert response.data["subtotal"] == "150.00" and len(response.data["items"]) == 2

    def test_rejects_items_from_two_shops(self, auth_client, live_deal):
        client, _ = auth_client()
        a, b = live_deal(), live_deal()
        response = client.post(CREATE, order_body((a, "1"), (b, "1")), format="json")
        assert response.data["error"]["code"] == "multiple_shops"
        assert stock(a) == (0, 0) and stock(b) == (0, 0)  # the whole order rolled back

    def test_delivery_needs_shop_delivery_and_adds_fee(self, auth_client, live_deal, merchant_shop):
        client, user = auth_client()
        address = Address.objects.create(user=user, address_line="Kumher Gate", city="Bharatpur", state="Rajasthan",
                                          pincode="321001", latitude=27.21, longitude=77.49)
        pickup_only = live_deal()
        response = client.post(CREATE, order_body((pickup_only, "1"), fulfilment="delivery", address=address.id), format="json")
        assert response.data["error"]["code"] in ("fulfilment_unavailable", "delivery_off")

        delivering = live_deal(merchant_shop(offers_delivery=True), fulfilment="both")
        response = client.post(CREATE, order_body((delivering, "1"), fulfilment="delivery", address=address.id), format="json")
        assert response.status_code == 201, response.data
        assert response.data["delivery_fee"] == "20.00" and response.data["total_amount"] == "80.00"
        assert "Kumher Gate" in response.data["delivery_address"]

    def test_cannot_use_someone_elses_address(self, auth_client, live_deal, merchant_shop):
        _, other = auth_client()
        address = Address.objects.create(user=other, address_line="x", city="Bharatpur", state="Rajasthan",
                                          pincode="321001", latitude=27.21, longitude=77.49)
        client, _ = auth_client()
        deal = live_deal(merchant_shop(offers_delivery=True), fulfilment="both")
        response = client.post(CREATE, order_body((deal, "1"), fulfilment="delivery", address=address.id), format="json")
        assert response.status_code == 404


@pytest.mark.django_db
class TestCoupons:
    @pytest.fixture
    def coupon(self):
        now = timezone.now()
        return Coupon.objects.create(code="bharat10", discount_type="percent", value=10, max_discount=50,
                                     min_order_amount=100, valid_from=now - timedelta(days=1), valid_until=now + timedelta(days=1))

    def test_percent_coupon(self, auth_client, live_deal, coupon):
        client, _ = auth_client()
        response = client.post(CREATE, order_body((live_deal(), "2"), coupon_code="BHARAT10"), format="json")
        assert response.data["coupon_discount"] == "12.00" and response.data["total_amount"] == "108.00"

    def test_once_per_customer(self, auth_client, live_deal, coupon):
        client, _ = auth_client()
        client.post(CREATE, order_body((live_deal(), "2"), coupon_code="BHARAT10"), format="json")
        response = client.post(CREATE, order_body((live_deal(), "2"), coupon_code="BHARAT10"), format="json")
        assert response.data["error"]["code"] == "coupon_already_used"

    def test_min_order(self, auth_client, live_deal, coupon):
        client, _ = auth_client()
        response = client.post(CREATE, order_body((live_deal(), "1"), coupon_code="BHARAT10"), format="json")
        assert response.data["error"]["code"] == "coupon_min_order"

    def test_check_endpoint(self, auth_client, live_deal, coupon):
        client, _ = auth_client()
        deal = live_deal()
        response = client.post("/api/v1/orders/check-coupon/", {"code": "bharat10", "shop": deal.shop_id, "subtotal": "600"})
        assert response.data["discount"] == Decimal("50.00")  # capped at max_discount


@pytest.mark.django_db
class TestOrderLifecycle:
    def test_pickup_cash_full_flow(self, auth_client, live_deal):
        client, customer = auth_client()
        deal = live_deal()
        merchant = deal.merchant_client
        order = client.post(CREATE, order_body((deal, "2")), format="json").data

        assert merchant.post(f"/api/v1/orders/{order['id']}/accept/").data["status"] == "confirmed"
        assert merchant.post(f"/api/v1/orders/{order['id']}/ready/").data["status"] == "ready"
        wrong = merchant.post(f"/api/v1/orders/{order['id']}/complete/", {"pickup_code": "9999" if order["pickup_code"] != "9999" else "0000"})
        assert wrong.data["error"]["code"] == "wrong_pickup_code"
        done = merchant.post(f"/api/v1/orders/{order['id']}/complete/", {"pickup_code": order["pickup_code"]})
        assert done.data["status"] == "completed" and done.data["payment_status"] == "paid"
        assert stock(deal) == (0, 2)
        commission = Commission.objects.get()
        assert commission.amount == Decimal("3.60")  # 3% of ₹120

    def test_merchant_does_not_see_pickup_code(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "1")), format="json").data
        merchant_view = deal.merchant_client.get(f"/api/v1/orders/{order['id']}/").data
        assert "pickup_code" not in merchant_view and merchant_view["customer_phone"].endswith("xxxxx")

    def test_customer_cancel_releases_stock(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2")), format="json").data
        assert client.post(f"/api/v1/orders/{order['id']}/cancel/").data["status"] == "cancelled"
        assert stock(deal) == (0, 0)

    def test_customer_cannot_cancel_after_accept(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2")), format="json").data
        deal.merchant_client.post(f"/api/v1/orders/{order['id']}/accept/")
        assert client.post(f"/api/v1/orders/{order['id']}/cancel/").data["error"]["code"] == "cannot_cancel"

    def test_other_merchant_gets_404(self, auth_client, live_deal):
        client, _ = auth_client()
        order = client.post(CREATE, order_body((live_deal(), "1")), format="json").data
        other = live_deal().merchant_client
        assert other.post(f"/api/v1/orders/{order['id']}/accept/").status_code == 404

    def test_unanswered_order_expires(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2")), format="json").data
        Order.objects.filter(pk=order["id"]).update(expires_at=timezone.now() - timedelta(minutes=1))
        assert services.expire_orders() == 1
        assert Order.objects.get(pk=order["id"]).status == "cancelled" and stock(deal) == (0, 0)


@pytest.mark.django_db
class TestOnlinePayment:
    def test_pay_then_shop_sees_order(self, auth_client, live_deal):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2"), payment_method="online"), format="json").data
        assert order["status"] == "pending_payment"
        assert not deal.shop.merchant.user.notifications.exists()  # not until paid

        response = pay(client, order)
        assert response.status_code == 200, response.data
        assert response.data["status"] == "paid" and response.data["reference"] == order["order_number"]
        refreshed = Order.objects.get(pk=order["id"])
        assert refreshed.status == "pending" and refreshed.payment_status == "paid"
        assert deal.shop.merchant.user.notifications.get().kind == "new_order"

    def test_bad_signature_rejected(self, auth_client, live_deal):
        client, _ = auth_client()
        order = client.post(CREATE, order_body((live_deal(), "1"), payment_method="online"), format="json").data
        checkout = client.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]}).data
        response = client.post("/api/v1/payments/verify/", {
            "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": "pay_x", "razorpay_signature": "forged",
        })
        assert response.data["error"]["code"] == "payment_verification_failed"
        assert Order.objects.get(pk=order["id"]).payment_status == "unpaid"

    def test_cannot_pay_someone_elses_order(self, auth_client, live_deal):
        client, _ = auth_client()
        order = client.post(CREATE, order_body((live_deal(), "1"), payment_method="online"), format="json").data
        stranger, _ = auth_client()
        response = stranger.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]})
        assert response.data["error"]["code"] == "not_payable"

    def test_shop_reject_refunds_paid_order(self, auth_client, live_deal, django_capture_on_commit_callbacks):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2"), payment_method="online"), format="json").data
        pay(client, order)
        with django_capture_on_commit_callbacks(execute=True):
            response = deal.merchant_client.post(f"/api/v1/orders/{order['id']}/reject/", {"reason": "Stock khatam"})
        assert response.data["status"] == "cancelled" and response.data["payment_status"] == "refunded"
        refund = Refund.objects.get()
        assert refund.amount == Decimal("120.00") and refund.status == "processed"
        assert stock(deal) == (0, 0)

    def test_late_payment_after_expiry_is_refunded(self, auth_client, live_deal, django_capture_on_commit_callbacks):
        client, _ = auth_client()
        order = client.post(CREATE, order_body((live_deal(), "1"), payment_method="online"), format="json").data
        checkout = client.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]}).data
        Order.objects.filter(pk=order["id"]).update(expires_at=timezone.now() - timedelta(minutes=1))
        services.expire_orders()
        with django_capture_on_commit_callbacks(execute=True):
            client.post("/api/v1/payments/verify/", {
                "razorpay_order_id": checkout["razorpay_order_id"], "razorpay_payment_id": "pay_late",
                "razorpay_signature": gateway.checkout_signature(checkout["razorpay_order_id"], "pay_late"),
            })
        assert Refund.objects.get().reason.startswith("Order was cancelled")

    def test_webhook_is_verified_and_idempotent(self, auth_client, live_deal, api_client, settings):
        import hashlib
        import hmac
        import json

        client, _ = auth_client()
        order = client.post(CREATE, order_body((live_deal(), "1"), payment_method="online"), format="json").data
        checkout = client.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]}).data
        body = json.dumps({"event": "payment.captured", "payload": {"payment": {"entity": {
            "id": "pay_hook", "order_id": checkout["razorpay_order_id"], "method": "upi"}}}}).encode()
        signature = hmac.new(settings.RAZORPAY_WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
        url = "/api/v1/payments/webhook/"
        headers = {"HTTP_X_RAZORPAY_SIGNATURE": signature, "HTTP_X_RAZORPAY_EVENT_ID": "evt_1"}

        assert api_client.post(url, body, content_type="application/json", HTTP_X_RAZORPAY_SIGNATURE="bad").status_code == 400
        assert api_client.post(url, body, content_type="application/json", **headers).data == {"status": "payment.captured"}
        assert api_client.post(url, body, content_type="application/json", **headers).data == {"status": "duplicate"}
        payment = Payment.objects.get()
        assert payment.status == "paid" and payment.method == "upi"
        assert Order.objects.get(pk=order["id"]).payment_status == "paid"

    def test_admin_refund_of_completed_order_reverses_commission(self, auth_client, live_deal, make_user,
                                                                  django_capture_on_commit_callbacks):
        client, _ = auth_client()
        deal = live_deal()
        order = client.post(CREATE, order_body((deal, "2"), payment_method="online"), format="json").data
        pay(client, order)
        merchant = deal.merchant_client
        merchant.post(f"/api/v1/orders/{order['id']}/accept/")
        merchant.post(f"/api/v1/orders/{order['id']}/ready/")
        merchant.post(f"/api/v1/orders/{order['id']}/complete/", {"pickup_code": order["pickup_code"]})
        admin = make_user(role="admin")

        partial = services.refund_completed_order(Order.objects.get(pk=order["id"]), Decimal("20"), "1 kg kharab", admin)
        assert partial.payment_status == "partially_refunded" and partial.status == "completed"
        with pytest.raises(Exception):
            services.refund_completed_order(partial, Decimal("500"), "too much", admin)
        full = services.refund_completed_order(partial, Decimal("100"), "rest", admin)
        assert full.status == "refunded" and Commission.objects.get().status == "reversed"


@pytest.mark.django_db
def test_dev_payment_only_with_fake_backend(auth_client, live_deal, settings):
    client, _ = auth_client()
    order = client.post(CREATE, order_body((live_deal(), "1"), payment_method="online"), format="json").data
    checkout = client.post("/api/v1/payments/create/", {"purpose": "order", "id": order["id"]}).data
    settings.PAYMENT_BACKEND = "razorpay"
    assert client.post("/api/v1/payments/dev-complete/", {"razorpay_order_id": checkout["razorpay_order_id"]}).status_code == 404
    settings.PAYMENT_BACKEND = "fake"
    assert client.post("/api/v1/payments/dev-complete/", {"razorpay_order_id": checkout["razorpay_order_id"]}).data["status"] == "paid"
