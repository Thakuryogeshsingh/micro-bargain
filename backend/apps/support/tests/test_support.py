from decimal import Decimal

import pytest

from apps.reservations import services as reservations
from apps.support import services
from apps.support.models import Complaint

URL = "/api/v1/support/"


@pytest.mark.django_db
class TestSupport:
    def test_ticket_thread(self, auth_client, make_user):
        client, user = auth_client()
        ticket = client.post(URL, {"category": "app", "subject": "OTP nahi aaya", "message": "Do baar try kiya"}).data
        assert ticket["ticket_number"].startswith("T-") and ticket["status"] == "open"

        staff = make_user(role="admin", is_staff=True)
        services.staff_reply(Complaint.objects.get(), staff, "Ab try kijiye", resolve=True)
        assert user.notifications.get().kind == "support_reply"

        # Replying to a resolved ticket reopens it.
        response = client.post(f"{URL}{ticket['id']}/message/", {"message": "Abhi bhi nahi"})
        assert response.data["status"] == "open"
        assert [m["is_staff_reply"] for m in response.data["messages"]] == [False, True, False]

    def test_payment_tickets_are_high_priority(self, auth_client):
        client, _ = auth_client()
        assert client.post(URL, {"category": "payment", "subject": "Refund", "message": "?"}).data["priority"] == "high"

    def test_link_only_own_reservation(self, auth_client, live_deal):
        client, customer = auth_client()
        reservation = reservations.create_reservation(customer, live_deal().id, Decimal("1"))
        ok = client.post(URL, {"category": "reservation", "subject": "s", "message": "m", "reservation": reservation.id})
        assert ok.status_code == 201
        stranger, _ = auth_client()
        bad = stranger.post(URL, {"category": "reservation", "subject": "s", "message": "m", "reservation": reservation.id})
        assert bad.status_code == 404

    def test_only_own_tickets_visible(self, auth_client):
        client, _ = auth_client()
        ticket = client.post(URL, {"category": "other", "subject": "s", "message": "m"}).data
        other, _ = auth_client()
        assert other.get(URL).data == [] and other.get(f"{URL}{ticket['id']}/").status_code == 404
