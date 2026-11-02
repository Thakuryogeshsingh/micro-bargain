import pytest

from apps.accounts.models import User
from apps.merchants.models import MerchantProfile
from apps.merchants.services import review_merchant

REGISTER = "/api/v1/merchants/register/"


@pytest.mark.django_db
class TestMerchantRegistration:
    def test_customer_account_becomes_pending_merchant(self, auth_client, fruits):
        client, user = auth_client()
        response = client.post(REGISTER, {"owner_name": "रमेश गुप्ता", "business_category": fruits.id})
        assert response.status_code == 201
        assert response.data["status"] == "pending"
        user.refresh_from_db()
        assert user.role == User.Role.MERCHANT
        assert user.name == "रमेश गुप्ता"

    def test_cannot_register_twice(self, auth_client, fruits):
        client, _ = auth_client()
        client.post(REGISTER, {"owner_name": "Ramesh", "business_category": fruits.id})
        response = client.post(REGISTER, {"owner_name": "Ramesh", "business_category": fruits.id})
        assert response.data["error"]["code"] == "already_merchant"

    def test_requires_login(self, api_client, fruits):
        response = api_client.post(REGISTER, {"owner_name": "Ramesh", "business_category": fruits.id})
        assert response.status_code == 401

    def test_profile_and_update(self, auth_client, fruits):
        client, _ = auth_client()
        client.post(REGISTER, {"owner_name": "Ramesh", "business_category": fruits.id})
        assert client.get("/api/v1/merchants/profile/").data["owner_name"] == "Ramesh"
        response = client.patch("/api/v1/merchants/profile/update/", {"owner_name": "Ramesh Gupta", "status": "approved"})
        assert response.status_code == 200
        assert response.data["owner_name"] == "Ramesh Gupta"
        # Status is read-only for merchants.
        assert response.data["status"] == "pending"

    def test_customers_cannot_open_merchant_profile(self, auth_client):
        client, _ = auth_client()
        assert client.get("/api/v1/merchants/profile/").status_code == 403

    def test_admin_review(self, auth_client, make_user, fruits):
        client, user = auth_client()
        client.post(REGISTER, {"owner_name": "Ramesh", "business_category": fruits.id})
        admin = make_user(role=User.Role.ADMIN)
        profile = review_merchant(MerchantProfile.objects.get(user=user), admin, approve=False, reason="Blurry ID")
        assert profile.status == "rejected" and profile.rejection_reason == "Blurry ID"
        profile = review_merchant(profile, admin, approve=True)
        assert profile.is_approved and profile.rejection_reason == "" and profile.reviewed_by == admin


@pytest.mark.django_db
def test_categories_are_seeded_and_public(api_client):
    response = api_client.get("/api/v1/categories/")
    assert response.status_code == 200
    slugs = [c["slug"] for c in response.data]
    assert slugs[:3] == ["fruits", "vegetables", "grocery"]
    assert len(slugs) == 10
