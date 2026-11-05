"""Business logic for notifications.

Every notification is first saved as an inbox row, then pushed to the user's phones by a Celery
task after the surrounding transaction commits. If the push fails, the inbox row still exists.
"""
import logging

from django.conf import settings
from django.db import transaction
from django.db.models import Count, F, Q
from django.utils import timezone

from apps.accounts.models import User
from apps.customers.models import CustomerProfile
from apps.shops.services import make_point

from .models import Device, Notification
from .push import send_push

logger = logging.getLogger(__name__)

Kind = Notification.Kind
PushStatus = Notification.PushStatus


# ---------- devices ----------

def register_device(user, token, platform, latitude=None, longitude=None):
    """Called when the app starts or the FCM token changes. A token moves to whoever logged in last."""
    device = Device.objects.filter(token=token).first() or Device(token=token)
    if device.user_id != user.id:
        device.location = None  # don't keep the previous user's position
    device.user = user
    device.platform = platform
    device.is_active = True
    device.last_seen_at = timezone.now()
    if latitude is not None and longitude is not None:
        device.location = make_point(latitude, longitude)
    device.save()
    return device


def unregister_device(user, token):
    """Called on logout so the phone stops receiving this user's notifications."""
    return Device.objects.filter(user=user, token=token).update(is_active=False)


# ---------- inbox ----------

def mark_read(user, pk=None):
    unread = user.notifications.filter(is_read=False)
    if pk is not None:
        unread = unread.filter(pk=pk)
    return unread.update(is_read=True, read_at=timezone.now())


# ---------- creating notifications ----------

def notify(user, kind, title, body, *, data=None, deal=None, push=True):
    notification = Notification.objects.create(
        user=user, kind=kind, title=title, body=body, data=data or {}, deal=deal,
        push_status=PushStatus.PENDING if push else PushStatus.SKIPPED,
        push_error="" if push else "Turned off by user",
    )
    if push:
        _push_after_commit([notification.id])
    return notification


def _push_after_commit(notification_ids):
    from .tasks import send_notifications

    # robust=True: if Redis is down the reservation still succeeds; the push is just lost (inbox row remains).
    transaction.on_commit(lambda: send_notifications.delay(notification_ids), robust=True)


def wants_order_updates(user):
    return not CustomerProfile.objects.filter(user=user, notify_order_updates=False).exists()


def _qty(value):
    text = f"{value:f}"
    return text.rstrip("0").rstrip(".") if "." in text else text


def reservation_event(reservation, kind):
    """Tell the other side about a reservation status change. Call inside the service's transaction."""
    product = reservation.deal.product.name
    shop = reservation.shop.name
    item = f"{_qty(reservation.quantity)} {reservation.unit} {product}"
    data = {"reservation_id": str(reservation.id), "reservation_number": reservation.reservation_number}

    if kind in (Kind.NEW_RESERVATION, Kind.RESERVATION_CANCELLED):
        recipient = reservation.shop.merchant.user
        push = True
        if kind == Kind.NEW_RESERVATION:
            title = f"नई बुकिंग {reservation.reservation_number}"
            when = f" पिकअप: {timezone.localtime(reservation.pickup_at):%I:%M %p}।" if reservation.pickup_at else ""
            body = f"ग्राहक ने {item} बुक किया (₹{reservation.total_amount})।{when} जल्दी कन्फर्म करें।"
        else:
            title = f"बुकिंग रद्द {reservation.reservation_number}"
            body = f"ग्राहक ने {item} की बुकिंग रद्द कर दी। स्टॉक वापस डील में जुड़ गया।"
    else:
        recipient = reservation.customer
        push = wants_order_updates(recipient)
        pickup_by = timezone.localtime(reservation.expires_at).strftime("%I:%M %p")
        title, body = {
            Kind.RESERVATION_CONFIRMED: ("बुकिंग कन्फर्म ✅", f"{shop} पर {item} तैयार है। {pickup_by} तक पिकअप करें।"),
            Kind.RESERVATION_REJECTED: ("बुकिंग अस्वीकार", f"{shop} ने {product} की बुकिंग अस्वीकार की। {reservation.closed_reason}"),
            Kind.RESERVATION_EXPIRED: ("बुकिंग का समय खत्म", f"{product} समय पर पिकअप नहीं हुआ, इसलिए बुकिंग रद्द हो गई।"),
            Kind.RESERVATION_COMPLETED: ("पिकअप पूरा 🎉", f"{shop} से {item} लिया। आपने ₹{reservation.savings} बचाए!"),
        }[kind]
    return notify(recipient, kind, title, body.strip(), data=data, push=push)


def shop_reviewed(shop):
    if shop.status == shop.Status.APPROVED:
        title, body, kind = "दुकान अप्रूव हो गई ✅", f"{shop.name} अब ग्राहकों को दिखेगी। पहली डील डालें!", Kind.SHOP_APPROVED
    else:
        title, body, kind = "दुकान अप्रूव नहीं हुई", f"{shop.name}: {shop.rejection_reason or 'विवरण देखें'}", Kind.SHOP_REJECTED
    return notify(shop.merchant.user, kind, title, body, data={"shop_id": str(shop.id)})


# ---------- new deal alerts ----------

def schedule_new_deal_alerts(deal):
    """Fan out "new deal" alerts once the deal goes live (now, or at its start time)."""
    from .tasks import fan_out_new_deal

    eta = max(timezone.now(), deal.starts_at)
    transaction.on_commit(lambda: fan_out_new_deal.apply_async(args=[deal.id], eta=eta), robust=True)


def _in_quiet_hours():
    start, end = settings.QUIET_HOURS
    hour = timezone.localtime().hour
    return start <= hour < end if start < end else hour >= start or hour < end


def notify_new_deal(deal_id):
    """Alert customers who favourited the shop, and customers whose phone is within their search radius."""
    from apps.deals.services import live_deals

    deal = live_deals().filter(pk=deal_id).first()
    if deal is None:  # paused, sold out or ended before the alert went out
        return 0
    shop = deal.shop
    customers = User.objects.filter(role=User.Role.CUSTOMER, is_active=True).exclude(
        notifications__deal=deal, notifications__kind__in=Notification.DEAL_KINDS
    )
    favourite_ids = set(
        customers.filter(favorite_shops__shop=shop, customer_profile__notify_favorite_shops=True)
        .values_list("id", flat=True)
    )
    nearby_ids = set(
        customers.filter(
            customer_profile__notify_nearby_deals=True,
            devices__is_active=True,
            # Each customer's own radius (1-10 km) from their profile.
            devices__location__dwithin=(shop.location, F("customer_profile__search_radius_m")),
        )
        .filter(
            Q(customer_profile__preferred_categories=None)
            | Q(customer_profile__preferred_categories=deal.product.category_id)
        )
        .values_list("id", flat=True)
    ) - favourite_ids
    if not favourite_ids and not nearby_ids:
        return 0

    day_start = timezone.localtime().replace(hour=0, minute=0, second=0, microsecond=0)
    capped = {
        row["user_id"]
        for row in Notification.objects.filter(
            user_id__in=favourite_ids | nearby_ids, kind__in=Notification.DEAL_KINDS, created_at__gte=day_start
        )
        .exclude(push_status=PushStatus.SKIPPED)
        .values("user_id")
        .annotate(n=Count("id"))
        if row["n"] >= settings.MAX_DEAL_ALERTS_PER_DAY
    }
    quiet = _in_quiet_hours()

    price = f"₹{deal.offer_price}/{deal.unit} ({deal.discount_percent:.0f}% off)"
    body = f"{deal.product.name} सिर्फ {price} — {shop.name}"
    data = {"deal_id": str(deal.id), "shop_id": str(shop.id)}
    rows = []
    for user_id in favourite_ids | nearby_ids:
        kind = Kind.FAVORITE_SHOP_DEAL if user_id in favourite_ids else Kind.NEARBY_DEAL
        title = f"❤️ {shop.name} की नई डील" if user_id in favourite_ids else "🔥 पास में नई डील"
        skip_reason = "Quiet hours" if quiet else "Daily limit reached" if user_id in capped else ""
        rows.append(Notification(
            user_id=user_id, kind=kind, title=title, body=body, data=data, deal=deal,
            push_status=PushStatus.SKIPPED if skip_reason else PushStatus.PENDING, push_error=skip_reason,
        ))
    # ignore_conflicts: the unique constraint drops anything a parallel run already created.
    Notification.objects.bulk_create(rows, ignore_conflicts=True)
    pending = list(
        Notification.objects.filter(deal=deal, kind__in=Notification.DEAL_KINDS, push_status=PushStatus.PENDING)
        .values_list("id", flat=True)
    )
    deliver(pending)
    return len(rows)


# ---------- delivery ----------

def deliver(notification_ids):
    """Push pending notifications to every active device of their users."""
    sent = 0
    for notification in Notification.objects.filter(id__in=notification_ids, push_status=PushStatus.PENDING):
        tokens = list(Device.objects.filter(user_id=notification.user_id, is_active=True).values_list("token", flat=True))
        if not tokens:
            _set_push_status(notification, PushStatus.SKIPPED, "No active device")
            continue
        data = {**notification.data, "kind": notification.kind, "notification_id": str(notification.id)}
        try:
            invalid = send_push(tokens, notification.title, notification.body, data)
        except Exception as exc:  # one bad push must not stop the rest
            logger.exception("Push %s failed", notification.id)
            _set_push_status(notification, PushStatus.FAILED, str(exc)[:255])
            continue
        if invalid:
            Device.objects.filter(token__in=invalid).update(is_active=False)
        if len(invalid) == len(tokens):
            _set_push_status(notification, PushStatus.FAILED, "All device tokens are invalid")
        else:
            _set_push_status(notification, PushStatus.SENT)
            sent += 1
    return sent


def _set_push_status(notification, status, error=""):
    notification.push_status = status
    notification.push_error = error
    notification.save(update_fields=["push_status", "push_error", "updated_at"])



def deal_ending_alerts():
    """Tell customers who favourited a shop that one of its deals ends in about half an hour (once per deal)."""
    from datetime import timedelta

    from apps.deals.services import live_deals

    now = timezone.now()
    sent = 0
    for deal in live_deals().filter(expires_at__gt=now + timedelta(minutes=20), expires_at__lte=now + timedelta(minutes=40)):
        already = Notification.objects.filter(deal=deal, kind=Kind.DEAL_ENDING).values("user_id")
        fans = User.objects.filter(favorite_shops__shop=deal.shop, is_active=True).exclude(id__in=already)
        for user in fans:
            Notification.objects.create(
                user=user, kind=Kind.DEAL_ENDING, deal=deal,
                title=f"⏰ {deal.product.name} की डील खत्म होने वाली है",
                body=f"{deal.shop.name} पर सिर्फ ₹{deal.offer_price}/{deal.unit} — 30 मिनट बाकी।",
                data={"deal_id": str(deal.id)},
            )
            sent += 1
    pending = Notification.objects.filter(kind=Kind.DEAL_ENDING, push_status=PushStatus.PENDING).values_list("id", flat=True)
    deliver(list(pending))
    return sent
