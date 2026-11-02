from datetime import timedelta
from decimal import Decimal
from unittest import mock

import pytest
from django.utils import timezone

from apps.customers.models import CustomerProfile
from apps.deals import services as deal_services
from apps.notifications import services
from apps.notifications.models import Device, Notification
from apps.reservations import services as reservation_services
from apps.shops.models import FavoriteShop
from apps.shops.services import review_shop
from conftest import BHARATPUR

Kind = Notification.Kind
DEVICES = "/api/v1/notifications/devices/"

# 0.009° of latitude is roughly 1 km.
ONE_KM_NORTH = (BHARATPUR[0] + 0.009, BHARATPUR[1])
FOUR_KM_NORTH = (BHARATPUR[0] + 0.036, BHARATPUR[1])


@pytest.fixture(autouse=True)
def _daytime():
    """Deal alerts are held back at night; pin the clock to noon so tests don't depend on when they run."""
    with mock.patch.object(services, "_in_quiet_hours", return_value=False):
        yield


@pytest.fixture
def pushes():
    with mock.patch.object(services, "send_push", return_value=[]) as send:
        yield send


@pytest.fixture
def customer(auth_client):
    """customer(position=None, **profile) -> (client, user) with a registered phone at that position."""

    def _make(position=None, **profile):
        client, user = auth_client()
        CustomerProfile.objects.create(user=user, **profile)
        body = {"token": f"token-{user.phone}", "platform": "android"}
        if position:
            body.update(latitude=position[0], longitude=position[1])
        assert client.post(DEVICES, body).status_code == 204
        return client, user

    return _make


def publish(merchant_shop, **deal_fields):
    client, shop, product = merchant_shop()
    fields = dict(normal_price=Decimal("100"), offer_price=Decimal("60"), quantity_total=Decimal("20"),
                  duration_minutes=120, publish=True)
    fields.update(deal_fields)
    return deal_services.create_deal(shop.merchant.user, shop=shop, product=product, **fields)


def alerts(user):
    return list(user.notifications.filter(kind__in=Notification.DEAL_KINDS).values_list("kind", "push_status"))


@pytest.mark.django_db
class TestDevices:
    def test_register_updates_same_token(self, customer):
        client, user = customer(BHARATPUR)
        client.post(DEVICES, {"token": f"token-{user.phone}", "platform": "android", "latitude": 27.3, "longitude": 77.5})
        device = Device.objects.get()
        assert device.user == user and round(device.location.y, 1) == 27.3

    def test_token_moves_to_new_user_without_old_location(self, customer, auth_client):
        _, first = customer(BHARATPUR)
        client, second = auth_client()
        client.post(DEVICES, {"token": f"token-{first.phone}"})
        device = Device.objects.get()
        assert device.user == second and device.location is None

    def test_needs_both_coordinates(self, auth_client):
        client, _ = auth_client()
        assert client.post(DEVICES, {"token": "t", "latitude": 27.2}).status_code == 400

    def test_unregister(self, customer):
        client, user = customer()
        assert client.post(DEVICES + "unregister/", {"token": f"token-{user.phone}"}).status_code == 204
        assert not Device.objects.get().is_active


@pytest.mark.django_db
class TestNewDealAlerts:
    def test_nearby_customer_gets_alert(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, near = customer(ONE_KM_NORTH)
        _, far = customer(FOUR_KM_NORTH)  # default radius is 2 km
        with django_capture_on_commit_callbacks(execute=True):
            deal = publish(merchant_shop)
        assert alerts(near) == [(Kind.NEARBY_DEAL, "sent")]
        assert alerts(far) == []
        title, body, data = pushes.call_args.args[1:]
        assert "पास में" in title and "₹60.00/kg (40% off)" in body and data["deal_id"] == str(deal.id)

    def test_uses_each_customers_radius(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, wide = customer(FOUR_KM_NORTH, search_radius_m=5000)
        with django_capture_on_commit_callbacks(execute=True):
            publish(merchant_shop)
        assert alerts(wide) == [(Kind.NEARBY_DEAL, "sent")]

    def test_favourite_shop_alert_once(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, fan = customer(ONE_KM_NORTH)  # nearby AND favourite: still one alert
        client, shop, product = merchant_shop()
        FavoriteShop.objects.create(user=fan, shop=shop)
        with django_capture_on_commit_callbacks(execute=True):
            deal_services.create_deal(
                shop.merchant.user, shop=shop, product=product, normal_price=Decimal("100"),
                offer_price=Decimal("60"), quantity_total=Decimal("20"), duration_minutes=120, publish=True,
            )
        assert alerts(fan) == [(Kind.FAVORITE_SHOP_DEAL, "sent")]

    def test_respects_preferences(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, muted = customer(ONE_KM_NORTH, notify_nearby_deals=False)
        with django_capture_on_commit_callbacks(execute=True):
            publish(merchant_shop)
        assert alerts(muted) == []

    def test_preferred_categories_filter(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        from apps.categories.models import Category

        _, user = customer(ONE_KM_NORTH)
        user.customer_profile.preferred_categories.set([Category.objects.get(slug="vegetables")])
        with django_capture_on_commit_callbacks(execute=True):
            publish(merchant_shop)  # fruits
        assert alerts(user) == []

    def test_daily_cap(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks, settings):
        settings.MAX_DEAL_ALERTS_PER_DAY = 1
        _, user = customer(ONE_KM_NORTH)
        with django_capture_on_commit_callbacks(execute=True):
            publish(merchant_shop)
        with django_capture_on_commit_callbacks(execute=True):
            publish(merchant_shop)
        assert sorted(status for _, status in alerts(user)) == ["sent", "skipped"]
        assert pushes.call_count == 1

    def test_quiet_hours_keep_inbox_only(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, user = customer(ONE_KM_NORTH)
        with mock.patch.object(services, "_in_quiet_hours", return_value=True):
            with django_capture_on_commit_callbacks(execute=True):
                publish(merchant_shop)
        assert alerts(user) == [(Kind.NEARBY_DEAL, "skipped")]
        pushes.assert_not_called()

    def test_resume_after_pause_does_not_alert_again(self, customer, merchant_shop, pushes,
                                                     django_capture_on_commit_callbacks):
        _, user = customer(ONE_KM_NORTH)
        with django_capture_on_commit_callbacks(execute=True):
            deal = publish(merchant_shop)
        merchant = deal.shop.merchant.user
        deal_services.change_status(deal, merchant, deal.Status.PAUSED)
        with django_capture_on_commit_callbacks(execute=True) as callbacks:
            deal_services.publish_deal(deal, merchant)
        assert callbacks == [] and len(alerts(user)) == 1

    def test_deal_ended_before_alert_sends_nothing(self, customer, merchant_shop, pushes):
        _, user = customer(ONE_KM_NORTH)
        deal = publish(merchant_shop)
        deal_services.change_status(deal, deal.shop.merchant.user, deal.Status.ENDED)
        assert services.notify_new_deal(deal.id) == 0


@pytest.mark.django_db
class TestReservationEvents:
    @pytest.fixture
    def reservation(self, customer, merchant_shop):
        _, user = customer()
        deal = publish(merchant_shop)
        return reservation_services.create_reservation(user, deal.id, Decimal("2"))

    def kinds(self, user):
        return list(user.notifications.order_by("id").values_list("kind", flat=True))

    def test_merchant_hears_about_new_and_cancelled(self, reservation):
        reservation_services.cancel(reservation)
        merchant = reservation.shop.merchant.user
        assert self.kinds(merchant) == [Kind.NEW_RESERVATION, Kind.RESERVATION_CANCELLED]
        assert "2 kg" in merchant.notifications.get(kind=Kind.NEW_RESERVATION).body

    def test_customer_hears_confirm_and_complete(self, reservation):
        reservation_services.confirm(reservation)
        reservation_services.complete(reservation, reservation.pickup_code)
        assert self.kinds(reservation.customer) == [Kind.RESERVATION_CONFIRMED, Kind.RESERVATION_COMPLETED]
        assert "₹80.00" in reservation.customer.notifications.get(kind=Kind.RESERVATION_COMPLETED).body

    def test_customer_hears_reject_and_expiry(self, reservation, customer):
        reservation_services.reject(reservation, "Stock khatam")
        assert "Stock khatam" in reservation.customer.notifications.get().body

        _, other = customer()
        second = reservation_services.create_reservation(other, reservation.deal_id, Decimal("1"))
        type(second).objects.filter(pk=second.pk).update(expires_at=timezone.now() - timedelta(minutes=1))
        reservation_services.expire_reservations()
        assert self.kinds(other) == [Kind.RESERVATION_EXPIRED]

    def test_order_updates_off_keeps_inbox_but_no_push(self, reservation):
        CustomerProfile.objects.filter(user=reservation.customer).update(notify_order_updates=False)
        reservation_services.confirm(reservation)
        notification = reservation.customer.notifications.get()
        assert notification.push_status == "skipped"

    def test_push_runs_after_commit(self, customer, merchant_shop, pushes, django_capture_on_commit_callbacks):
        _, user = customer()
        deal = publish(merchant_shop)
        with django_capture_on_commit_callbacks(execute=True):
            reservation_services.create_reservation(user, deal.id, Decimal("2"))
        assert deal.shop.merchant.user.notifications.get().push_status == "skipped"  # merchant has no device
        assert pushes.call_count == 0


@pytest.mark.django_db
class TestDelivery:
    def test_invalid_tokens_are_deactivated(self, customer):
        _, user = customer()
        notification = services.notify(user, Kind.SHOP_APPROVED, "t", "b")
        with mock.patch.object(services, "send_push", return_value=[f"token-{user.phone}"]):
            services.deliver([notification.id])
        notification.refresh_from_db()
        assert notification.push_status == "failed" and not Device.objects.get().is_active

    def test_provider_error_marks_failed(self, customer):
        _, user = customer()
        notification = services.notify(user, Kind.SHOP_APPROVED, "t", "b")
        with mock.patch.object(services, "send_push", side_effect=RuntimeError("FCM down")):
            services.deliver([notification.id])
        notification.refresh_from_db()
        assert notification.push_status == "failed" and notification.push_error == "FCM down"

    def test_console_backend_marks_sent(self, customer):
        _, user = customer()
        notification = services.notify(user, Kind.SHOP_APPROVED, "t", "b")
        assert services.deliver([notification.id]) == 1

    def test_shop_review_notifies_merchant(self, merchant_shop, make_user):
        _, shop, _ = merchant_shop(approved=False)
        review_shop(shop, make_user(), approve=True)
        assert shop.merchant.user.notifications.get().kind == Kind.SHOP_APPROVED


@pytest.mark.django_db
class TestInboxApi:
    def test_list_unread_and_mark_read(self, auth_client):
        client, user = auth_client()
        first = services.notify(user, Kind.SHOP_APPROVED, "a", "b")
        services.notify(user, Kind.SHOP_APPROVED, "c", "d")
        assert client.get("/api/v1/notifications/").data["count"] == 2
        assert client.get("/api/v1/notifications/unread-count/").data == {"unread": 2}
        assert client.post(f"/api/v1/notifications/{first.id}/read/").data == {"marked_read": 1}
        assert client.get("/api/v1/notifications/?is_read=false").data["count"] == 1
        assert client.post("/api/v1/notifications/read-all/").data == {"marked_read": 1}

    def test_cannot_read_others(self, auth_client):
        _, owner = auth_client()
        other_client, _ = auth_client()
        notification = services.notify(owner, Kind.SHOP_APPROVED, "a", "b")
        assert other_client.get("/api/v1/notifications/").data["count"] == 0
        assert other_client.post(f"/api/v1/notifications/{notification.id}/read/").status_code == 404
