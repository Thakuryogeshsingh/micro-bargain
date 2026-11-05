from datetime import timedelta
from decimal import Decimal

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.customers import services as customers
from apps.quality import services
from apps.quality.models import QualityComplaint
from apps.reservations import services as reservations

GIF = b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x00\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"


def photo():
    return SimpleUploadedFile("bad.gif", GIF, content_type="image/gif")


def bought(customer, deal):
    reservation = reservations.create_reservation(customer, deal.id, Decimal("2"))
    reservations.confirm(reservation)
    reservations.complete(reservation, reservation.pickup_code)
    return reservation


def complain(client, reservation):
    return client.post("/api/v1/quality/complaints/", {"reservation": reservation.id, "reason": "stale", "photo": photo()},
                       format="multipart")


@pytest.mark.django_db
class TestComplaints:
    def test_shop_refunds_to_wallet(self, auth_client, live_deal):
        client, customer = auth_client()
        deal = live_deal()
        reservation = bought(customer, deal)
        response = complain(client, reservation)
        assert response.status_code == 201, response.data
        assert response.data["amount_paid"] == "120.00"
        merchant = deal.merchant_client
        assert deal.shop.merchant.user.notifications.filter(kind="quality_complaint").exists()
        listed = merchant.get("/api/v1/quality/shop-complaints/").data["results"]
        assert listed[0]["status"] == "open"
        wallet_before = customers.wallet_balance(customer)
        data = merchant.post(f"/api/v1/quality/complaints/{listed[0]['id']}/respond/", {"accept": True, "amount": "50"}).data
        assert data["status"] == "refunded" and data["refund_amount"] == "50.00"
        assert customers.wallet_balance(customer) - wallet_before == Decimal("50")
        refunds = client.get("/api/v1/customers/refunds/").data
        assert refunds["refunds"][0]["method"] == "wallet" and refunds["refunds"][0]["amount"] == Decimal("50")
        deal.shop.refresh_from_db()
        assert deal.shop.quality_score == 0  # 1 purchase, 1 upheld complaint

    def test_one_complaint_per_purchase_and_time_limit(self, auth_client, live_deal):
        client, customer = auth_client()
        reservation = bought(customer, live_deal())
        assert complain(client, reservation).status_code == 201
        assert complain(client, reservation).status_code == 400
        other = bought(customer, live_deal())
        type(other).objects.filter(pk=other.pk).update(completed_at=timezone.now() - timedelta(hours=49))
        assert complain(client, other).status_code == 400

    def test_photo_required(self, auth_client, live_deal):
        client, customer = auth_client()
        reservation = bought(customer, live_deal())
        assert client.post("/api/v1/quality/complaints/", {"reservation": reservation.id, "reason": "stale"}).status_code == 400

    def test_dispute_then_admin_rejects(self, auth_client, live_deal, make_user):
        client, customer = auth_client()
        deal = live_deal()
        complaint_id = complain(client, bought(customer, deal)).data["id"]
        merchant = deal.merchant_client
        assert merchant.post(f"/api/v1/quality/complaints/{complaint_id}/respond/", {"accept": False}).status_code == 400  # needs a note
        data = merchant.post(f"/api/v1/quality/complaints/{complaint_id}/respond/", {"accept": False, "note": "Fresh at pickup"}).data
        assert data["status"] == "disputed"
        admin = make_user(role="admin")
        services.admin_decide(QualityComplaint.objects.get(pk=complaint_id), admin, refund=False, note="Photo unclear")
        assert QualityComplaint.objects.get(pk=complaint_id).status == "rejected"
        assert customer.notifications.filter(kind="quality_complaint").count() == 2

    def test_unanswered_complaint_refunded_automatically(self, auth_client, live_deal):
        client, customer = auth_client()
        complaint_id = complain(client, bought(customer, live_deal())).data["id"]
        QualityComplaint.objects.filter(pk=complaint_id).update(created_at=timezone.now() - timedelta(hours=25))
        before = customers.wallet_balance(customer)
        assert services.auto_refund_unanswered() == 1
        assert customers.wallet_balance(customer) - before == Decimal("120")

    def test_other_shop_cannot_respond(self, auth_client, live_deal):
        client, customer = auth_client()
        complaint_id = complain(client, bought(customer, live_deal())).data["id"]
        stranger = live_deal().merchant_client
        assert stranger.post(f"/api/v1/quality/complaints/{complaint_id}/respond/", {"accept": True}).status_code == 404


@pytest.mark.django_db
class TestOnboarding:
    def test_steps_submit_and_approval_notifies(self, merchant_shop, make_user):
        from apps.shops.models import ShopDocument
        from apps.shops.services import review_shop

        client, shop, _ = merchant_shop(approved=False)
        status = client.get("/api/v1/merchants/onboarding/").data
        assert [s["done"] for s in status["steps"]] == [True, True, False, False]
        assert client.post("/api/v1/merchants/onboarding/").status_code == 400

        for doc_type in ("shop_photo", "id_proof"):
            ShopDocument.objects.create(shop=shop, doc_type=doc_type, file=photo())
        assert client.patch("/api/v1/merchants/profile/update/", {"upi_id": "bad"}).status_code == 400
        assert client.patch("/api/v1/merchants/profile/update/", {"upi_id": "ramesh@okaxis"}).status_code == 200
        submitted = client.post("/api/v1/merchants/onboarding/").data
        assert submitted["complete"] and submitted["submitted_at"]

        review_shop(shop, make_user(role="admin"), approve=True)
        merchant = shop.merchant
        merchant.refresh_from_db()
        assert merchant.status == "approved"
        assert merchant.user.notifications.filter(kind="shop_approved").count() == 1

    def test_admin_approving_merchant_without_shop_notifies(self, make_user, fruits):
        from apps.merchants.models import MerchantProfile
        from apps.merchants.services import review_merchant

        user = make_user(role="merchant")
        profile = MerchantProfile.objects.create(user=user, owner_name="Sita", business_category=fruits)
        review_merchant(profile, make_user(role="admin"), approve=True)
        assert user.notifications.filter(kind="merchant_approved").exists()


@pytest.mark.django_db
class TestOrderForSomeoneElse:
    def _address(self, client, lat=27.2152, lng=77.4890):
        return client.post("/api/v1/customers/addresses/", {
            "label": "Mummy", "address_line": "Ranjeet Nagar", "city": "Bharatpur", "state": "Rajasthan", "pincode": "321001",
            "latitude": lat, "longitude": lng, "contact_name": "Sunita", "contact_phone": "9812345678",
        }).data

    def test_recipient_saved_on_order(self, auth_client, live_deal, merchant_shop):
        client, _ = auth_client()
        address = self._address(client)
        assert address["contact_name"] == "Sunita"
        deal = live_deal(merchant_shop(offers_delivery=True), fulfilment="both")
        order = client.post("/api/v1/orders/create/", {
            "items": [{"deal": deal.id, "quantity": "1"}], "payment_method": "cash", "fulfilment": "delivery", "address": address["id"],
        }, format="json").data
        assert order["recipient_name"] == "Sunita" and order["recipient_phone"] == "9812345678"

    def test_too_far_for_delivery(self, auth_client, live_deal, merchant_shop):
        client, _ = auth_client()
        jaipur = self._address(client, 26.9124, 75.7873)
        deal = live_deal(merchant_shop(offers_delivery=True), fulfilment="both")
        response = client.post("/api/v1/orders/create/", {
            "items": [{"deal": deal.id, "quantity": "1"}], "payment_method": "cash", "fulfilment": "delivery", "address": jaipur["id"],
        }, format="json")
        assert response.status_code == 400 and "km" in str(response.data)


@pytest.mark.django_db
def test_refund_policy_page(client):
    body = client.get("/legal/refunds/").content.decode()
    assert "48 hours" in body and "wallet" in body
