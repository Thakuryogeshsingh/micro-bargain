from django.conf import settings
from django.db import models

from common.models import TimeStampedModel


class Complaint(TimeStampedModel):
    """A help request from a customer or merchant, with a message thread."""

    class Category(models.TextChoices):
        ORDER = "order", "Order"
        RESERVATION = "reservation", "Reservation / pickup"
        PAYMENT = "payment", "Payment / refund"
        SHOP = "shop", "Shop or product quality"
        ACCOUNT = "account", "Account / login"
        APP = "app", "App problem"
        OTHER = "other", "Other"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        IN_PROGRESS = "in_progress", "In progress"
        RESOLVED = "resolved", "Resolved"
        CLOSED = "closed", "Closed"

    class Priority(models.TextChoices):
        NORMAL = "normal", "Normal"
        HIGH = "high", "High"

    ticket_number = models.CharField(max_length=12, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="complaints")
    category = models.CharField(max_length=15, choices=Category.choices)
    subject = models.CharField(max_length=150)
    order = models.ForeignKey("orders.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="complaints")
    reservation = models.ForeignKey(
        "reservations.DealReservation", null=True, blank=True, on_delete=models.SET_NULL, related_name="complaints"
    )
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.OPEN, db_index=True)
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.NORMAL)
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="assigned_complaints",
        limit_choices_to={"is_staff": True},
    )
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.ticket_number}: {self.subject}"


class ComplaintMessage(models.Model):
    complaint = models.ForeignKey(Complaint, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    is_staff_reply = models.BooleanField(default=False)
    message = models.TextField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "id"]

    def __str__(self):
        return f"{'Support' if self.is_staff_reply else 'User'}: {self.message[:40]}"
