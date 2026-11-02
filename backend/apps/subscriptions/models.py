from django.db import models

from common.models import TimeStampedModel


class Plan(TimeStampedModel):
    """Merchant plans (doc section 13.2). Prices are test prices; change them in the admin."""

    class Analytics(models.TextChoices):
        BASIC = "basic", "Basic deal analytics"
        SALES = "sales", "Sales analytics"
        ADVANCED = "advanced", "Advanced analytics"

    FREE = "free"

    code = models.SlugField(max_length=20, unique=True)
    name = models.CharField(max_length=50)
    price_monthly = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    max_active_deals = models.PositiveIntegerField(null=True, blank=True, help_text="Empty = unlimited")
    analytics = models.CharField(max_length=10, choices=Analytics.choices, default=Analytics.BASIC)
    featured_listing = models.BooleanField(default=False, help_text="Deals get the featured boost in search")
    priority_support = models.BooleanField(default=False)
    sort_order = models.PositiveSmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["sort_order"]

    def __str__(self):
        return f"{self.name} (₹{self.price_monthly}/month)"


class MerchantSubscription(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING_PAYMENT = "pending_payment", "Waiting for payment"
        ACTIVE = "active", "Active"
        EXPIRED = "expired", "Expired"
        CANCELLED = "cancelled", "Cancelled"

    merchant = models.ForeignKey("merchants.MerchantProfile", on_delete=models.PROTECT, related_name="subscriptions")
    plan = models.ForeignKey(Plan, on_delete=models.PROTECT, related_name="subscriptions")
    months = models.PositiveSmallIntegerField(default=1)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING_PAYMENT, db_index=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["merchant", "status", "ends_at"])]

    def __str__(self):
        return f"{self.merchant} on {self.plan.code} ({self.status})"
