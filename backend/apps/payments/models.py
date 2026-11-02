from django.conf import settings
from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel


class Payment(TimeStampedModel):
    """One payment attempt through the gateway. An order can have several attempts; at most one is paid."""

    class Purpose(models.TextChoices):
        ORDER = "order", "Order"
        SUBSCRIPTION = "subscription", "Merchant plan"
        ADVERTISEMENT = "advertisement", "Promotion"

    class Status(models.TextChoices):
        CREATED = "created", "Created"
        PAID = "paid", "Paid"
        FAILED = "failed", "Failed"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="payments")
    purpose = models.CharField(max_length=15, choices=Purpose.choices)
    order = models.ForeignKey("orders.Order", null=True, blank=True, on_delete=models.PROTECT, related_name="payments")
    subscription = models.ForeignKey(
        "subscriptions.MerchantSubscription", null=True, blank=True, on_delete=models.PROTECT, related_name="payments"
    )
    advertisement = models.ForeignKey(
        "advertisements.Advertisement", null=True, blank=True, on_delete=models.PROTECT, related_name="payments"
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="INR")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.CREATED, db_index=True)
    gateway_order_id = models.CharField(max_length=64, unique=True)
    gateway_payment_id = models.CharField(max_length=64, blank=True, db_index=True)
    method = models.CharField(max_length=20, blank=True)  # upi / card / netbanking, as reported by the gateway
    error = models.CharField(max_length=255, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        # If a customer manages to pay twice for one order, both rows are "paid" and the second is refunded.
        constraints = [models.CheckConstraint(condition=Q(amount__gt=0), name="payment_amount_positive")]

    def __str__(self):
        return f"{self.purpose} ₹{self.amount} ({self.status})"


class Refund(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PROCESSED = "processed", "Processed"
        FAILED = "failed", "Failed"

    payment = models.ForeignKey(Payment, on_delete=models.PROTECT, related_name="refunds")
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reason = models.CharField(max_length=255)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True)
    gateway_refund_id = models.CharField(max_length=64, blank=True, db_index=True)
    error = models.CharField(max_length=255, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.CheckConstraint(condition=Q(amount__gt=0), name="refund_amount_positive")]

    def __str__(self):
        return f"Refund ₹{self.amount} ({self.status})"


class WebhookEvent(models.Model):
    """Every gateway webhook we processed, keyed by its event id, so retries are ignored (idempotency)."""

    event_id = models.CharField(max_length=64, unique=True)
    event = models.CharField(max_length=50)
    payload = models.JSONField()
    received_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.event} {self.event_id}"
