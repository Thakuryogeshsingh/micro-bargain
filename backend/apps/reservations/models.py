from django.conf import settings
from django.db import models
from django.db.models import Q

from apps.products.models import Product
from common.models import TimeStampedModel


class DealReservation(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Waiting for shop"
        CONFIRMED = "confirmed", "Confirmed by shop"
        COMPLETED = "completed", "Picked up"
        REJECTED = "rejected", "Rejected by shop"
        CANCELLED = "cancelled", "Cancelled by customer"
        EXPIRED = "expired", "Expired"

    OPEN_STATUSES = (Status.PENDING, Status.CONFIRMED)

    reservation_number = models.CharField(max_length=12, unique=True)
    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="reservations")
    deal = models.ForeignKey("deals.Deal", on_delete=models.PROTECT, related_name="reservations")
    shop = models.ForeignKey("shops.Shop", on_delete=models.PROTECT, related_name="reservations")

    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=10, choices=Product.Unit.choices)
    # Prices are copied at reservation time so later deal edits do not change what the customer agreed to.
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    normal_unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)

    pickup_code = models.CharField(max_length=4)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    expires_at = models.DateTimeField()
    confirmed_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    closed_reason = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status", "expires_at"]),
            models.Index(fields=["shop", "status"]),
            models.Index(fields=["customer", "status"]),
        ]
        constraints = [
            models.CheckConstraint(condition=Q(quantity__gt=0), name="reservation_quantity_positive"),
            # One open reservation per customer per deal: stops double taps creating two holds.
            models.UniqueConstraint(
                fields=["customer", "deal"],
                condition=Q(status__in=["pending", "confirmed"]),
                name="one_open_reservation_per_deal",
            ),
        ]

    def __str__(self):
        return f"{self.reservation_number} ({self.status})"

    @property
    def savings(self):
        return (self.normal_unit_price - self.unit_price) * self.quantity
