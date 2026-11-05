from django.conf import settings
from django.contrib.gis.db import models
from django.db.models import Q
from django.utils import timezone

from common.models import TimeStampedModel


class Device(TimeStampedModel):
    """A phone that can receive push notifications (one FCM token per app install)."""

    class Platform(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="devices")
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=10, choices=Platform.choices, default=Platform.ANDROID)
    # Last known position, sent by the app when it opens. Used for "new deal near you" alerts.
    location = models.PointField(geography=True, srid=4326, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-last_seen_at"]

    def __str__(self):
        return f"{self.platform} device of {self.user.phone}"


class Notification(TimeStampedModel):
    """One message in a user's in-app inbox. Push delivery status is tracked on the same row."""

    class Kind(models.TextChoices):
        NEARBY_DEAL = "nearby_deal", "New deal nearby"
        FAVORITE_SHOP_DEAL = "favorite_shop_deal", "New deal from a favourite shop"
        NEW_RESERVATION = "new_reservation", "New reservation (shop)"
        RESERVATION_CANCELLED = "reservation_cancelled", "Reservation cancelled (shop)"
        RESERVATION_CONFIRMED = "reservation_confirmed", "Reservation confirmed"
        RESERVATION_REJECTED = "reservation_rejected", "Reservation rejected"
        RESERVATION_EXPIRED = "reservation_expired", "Reservation expired"
        RESERVATION_COMPLETED = "reservation_completed", "Pickup completed"
        SHOP_APPROVED = "shop_approved", "Shop approved"
        SHOP_REJECTED = "shop_rejected", "Shop rejected"
        NEW_REVIEW = "new_review", "New review (shop)"
        NEW_ORDER = "new_order", "New order (shop)"
        ORDER_CANCELLED = "order_cancelled", "Order cancelled (shop)"
        ORDER_UPDATE = "order_update", "Order status update"
        REFUND = "refund", "Refund issued"
        SUBSCRIPTION_ACTIVE = "subscription_active", "Plan activated"
        AD_ACTIVE = "ad_active", "Promotion live"
        SUPPORT_REPLY = "support_reply", "Support reply"
        REFERRAL_REWARD = "referral_reward", "Referral reward"
        HAPPY_HOUR = "happy_hour", "Happy hour started"
        PLUS_ACTIVE = "plus_active", "Bargain Plus active"
        DEAL_ENDING = "deal_ending", "Deal ending soon"
        CASHBACK = "cashback", "Cashback credited"

    DEAL_KINDS = (Kind.NEARBY_DEAL, Kind.FAVORITE_SHOP_DEAL)

    class PushStatus(models.TextChoices):
        PENDING = "pending", "Pending"
        SENT = "sent", "Sent"
        FAILED = "failed", "Failed"
        SKIPPED = "skipped", "Skipped"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=30, choices=Kind.choices)
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=255)
    # Ids the app needs to open the right screen, e.g. {"deal_id": "12"}. Values are strings (FCM requirement).
    data = models.JSONField(default=dict, blank=True)
    deal = models.ForeignKey("deals.Deal", on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)
    push_status = models.CharField(max_length=10, choices=PushStatus.choices, default=PushStatus.PENDING)
    push_error = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "is_read"]), models.Index(fields=["user", "kind", "created_at"])]
        constraints = [
            # A customer hears about a given deal at most once, even if it is both nearby and from a favourite shop.
            models.UniqueConstraint(
                fields=["user", "deal"],
                condition=Q(kind__in=["nearby_deal", "favorite_shop_deal"]),
                name="one_alert_per_deal_per_user",
            ),
        ]

    def __str__(self):
        return f"{self.kind} for {self.user.phone}"
