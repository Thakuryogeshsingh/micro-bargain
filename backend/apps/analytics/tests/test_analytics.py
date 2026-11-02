from decimal import Decimal
from io import BytesIO

import pytest
from openpyxl import load_workbook

from apps.commissions.models import CommissionRule
from apps.reservations import services as reservations


@pytest.fixture
def sale(auth_client, live_deal):
    """One completed ₹120 pickup (2 kg at ₹60 instead of ₹100)."""
    _, customer = auth_client()
    deal = live_deal()
    reservation = reservations.create_reservation(customer, deal.id, Decimal("2"))
    reservations.confirm(reservation)
    reservations.complete(reservation, reservation.pickup_code)
    return deal


@pytest.mark.django_db
class TestAdminReports:
    def test_dashboard_numbers(self, sale, auth_client):
        admin, _ = auth_client(role="admin")
        data = admin.get("/api/v1/analytics/dashboard/").data
        assert data["completed_reservations"] == 1
        assert data["total_transaction_value"] == Decimal("120.00")
        assert data["customer_savings"] == Decimal("80.00")
        assert data["commission_revenue"] == Decimal("3.60")
        assert data["active_shops"] == 1 and data["active_deals"] == 1

    def test_city_filter(self, sale, auth_client):
        admin, _ = auth_client(role="admin")
        assert admin.get("/api/v1/analytics/dashboard/", {"city": "Jaipur"}).data["completed_reservations"] == 0

    def test_category_commission_rule(self, auth_client, live_deal, fruits):
        CommissionRule.objects.create(category=fruits, rate_percent=Decimal("5"))
        _, customer = auth_client()
        reservation = reservations.create_reservation(customer, live_deal().id, Decimal("2"))
        reservations.confirm(reservation)
        reservations.complete(reservation, reservation.pickup_code)
        assert reservation.commission.amount == Decimal("6.00")

    def test_reports_and_excel(self, sale, auth_client):
        admin, _ = auth_client(role="admin")
        merchants = admin.get("/api/v1/analytics/merchants/").data
        assert merchants[0]["revenue"] == Decimal("120.00") and merchants[0]["deal_conversion_pct"] == 100
        deals = admin.get("/api/v1/analytics/deals/").data
        assert deals["most_purchased"][0]["quantity_sold"] == Decimal("2.00")
        customers = admin.get("/api/v1/analytics/customers/").data
        assert customers["active_customers"] == 1 and customers["popular_categories"][0]["category"] == "Fruits"

        response = admin.get("/api/v1/analytics/merchants/", {"export": "xlsx"})
        assert response["Content-Type"].startswith("application/vnd.openxmlformats")
        sheet = load_workbook(BytesIO(response.content))["Merchants"]
        assert sheet["A1"].value == "Shop" and sheet["A2"].value == "Gupta Fruits"

    def test_admin_only(self, auth_client):
        customer, _ = auth_client()
        assert customer.get("/api/v1/analytics/dashboard/").status_code == 403

    def test_admin_html_dashboard(self, sale, client, make_user):
        staff = make_user(role="admin", is_staff=True, is_superuser=True)
        client.force_login(staff)
        response = client.get("/admin/dashboard/?city=Bharatpur&date_from=bad")
        assert response.status_code == 200 and b"Platform revenue" in response.content
        download = client.get("/admin/reports/deals.xlsx")
        assert download.status_code == 200


@pytest.mark.django_db
class TestMerchantSales:
    def test_needs_paid_plan(self, sale):
        client = sale.merchant_client
        assert client.get("/api/v1/analytics/merchant-sales/").data["error"]["code"] == "upgrade_required"

    def test_basic_plan_sees_sales(self, sale):
        from datetime import timedelta

        from django.utils import timezone

        from apps.subscriptions.models import MerchantSubscription, Plan

        now = timezone.now()
        MerchantSubscription.objects.create(
            merchant=sale.shop.merchant, plan=Plan.objects.get(code="basic"), amount=199, status="active",
            starts_at=now - timedelta(days=1), ends_at=now + timedelta(days=29),
        )
        data = sale.merchant_client.get("/api/v1/analytics/merchant-sales/", {"days": 7}).data
        assert data["total_sales"] == Decimal("120.00") and data["daily"][0]["transactions"] == 1
        assert data["top_products"][0]["sales"] == Decimal("120.00")
