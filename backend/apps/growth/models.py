from decimal import Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from common.models import TimeStampedModel


class PriceAlert(TimeStampedModel):
    """"Tell me when paneer is below ₹300 near me." Checked whenever deals go live."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="price_alerts")
    query = models.CharField(max_length=60)
    max_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal("1"))])
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    is_active = models.BooleanField(default=True)
    notified_deals = models.ManyToManyField("deals.Deal", blank=True, related_name="+")
    last_notified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]


class GroupDeal(TimeStampedModel):
    """Mohalla deal: when `target` neighbours join, everyone who buys gets `extra_percent` back in their wallet."""

    deal = models.OneToOneField("deals.Deal", on_delete=models.CASCADE, related_name="group")
    target = models.PositiveSmallIntegerField(validators=[MinValueValidator(2), MaxValueValidator(50)])
    extra_percent = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(30)])
    unlocked_at = models.DateTimeField(null=True, blank=True)

    @property
    def is_unlocked(self):
        return self.unlocked_at is not None


class GroupMember(TimeStampedModel):
    group = models.ForeignKey(GroupDeal, on_delete=models.CASCADE, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="group_memberships")
    rewarded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["group", "user"], name="one_join_per_group")]


class LoyaltyAccount(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="loyalty")
    points = models.PositiveIntegerField(default=0)
    streak_days = models.PositiveSmallIntegerField(default=0)
    best_streak = models.PositiveSmallIntegerField(default=0)
    last_purchase_date = models.DateField(null=True, blank=True)


class LoyaltyEntry(TimeStampedModel):
    class Kind(models.TextChoices):
        PURCHASE = "purchase", "Purchase"
        STREAK = "streak", "Streak bonus"
        REDEEM = "redeem", "Redeemed to wallet"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="loyalty_entries")
    kind = models.CharField(max_length=10, choices=Kind.choices)
    points = models.IntegerField()
    reference = models.CharField(max_length=30, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        verbose_name_plural = "loyalty entries"


class Broadcast(TimeStampedModel):
    """A notification the team sends to many users at once (e.g. a Diwali offer to everyone in a city)."""

    class Audience(models.TextChoices):
        CUSTOMERS = "customers", "All customers"
        MERCHANTS = "merchants", "All shop owners"
        EVERYONE = "everyone", "Everyone"

    title = models.CharField(max_length=80)
    body = models.CharField(max_length=240)
    audience = models.CharField(max_length=10, choices=Audience.choices, default=Audience.CUSTOMERS)
    city = models.CharField(max_length=80, blank=True, help_text="Only users with an address / shop in this city (blank = all)")
    send_at = models.DateTimeField(null=True, blank=True, help_text="Blank = send when you press 'Send now'")
    sent_at = models.DateTimeField(null=True, blank=True)
    sent_count = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title


class Campaign(TimeStampedModel):
    """Festival campaign: a home-screen banner (and optionally a coupon + broadcast) that switch on and off by date."""

    name = models.CharField(max_length=80)
    title = models.CharField(max_length=80, help_text="Banner headline, e.g. 'Diwali Dhamaka'")
    subtitle = models.CharField(max_length=140, blank=True)
    color = models.CharField(max_length=7, default="#0A0A0A", help_text="Banner colour, e.g. #E11D48")
    image = models.ImageField(upload_to="campaigns/", blank=True)
    coupon = models.ForeignKey("orders.Coupon", null=True, blank=True, on_delete=models.SET_NULL, related_name="+",
                               help_text="Switched on during the campaign and off after it")
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField()
    announce = models.BooleanField(default=False, help_text="Send a notification to all customers when it starts")
    announced_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-starts_at"]

    def __str__(self):
        return self.name
