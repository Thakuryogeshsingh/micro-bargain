from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel


class CommissionRule(TimeStampedModel):
    """Platform commission %. A rule for a category beats the default rule (category empty)."""

    category = models.OneToOneField(
        "categories.Category", null=True, blank=True, on_delete=models.CASCADE, related_name="commission_rule"
    )
    rate_percent = models.DecimalField(max_digits=4, decimal_places=2)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(rate_percent__gte=0) & Q(rate_percent__lte=30), name="commission_rate_range"),
            models.UniqueConstraint(fields=["is_active"], condition=Q(category=None, is_active=True), name="one_default_commission_rule"),
        ]

    def __str__(self):
        return f"{self.category or 'Default'}: {self.rate_percent}%"


class Commission(TimeStampedModel):
    """Platform's share of one completed transaction (an order, or a reservation picked up at the shop)."""

    class Status(models.TextChoices):
        PENDING = "pending", "Not settled yet"
        SETTLED = "settled", "Settled"
        REVERSED = "reversed", "Reversed (refund)"

    shop = models.ForeignKey("shops.Shop", on_delete=models.PROTECT, related_name="commissions")
    order = models.OneToOneField("orders.Order", null=True, blank=True, on_delete=models.PROTECT, related_name="commission")
    reservation = models.OneToOneField(
        "reservations.DealReservation", null=True, blank=True, on_delete=models.PROTECT, related_name="commission"
    )
    transaction_amount = models.DecimalField(max_digits=12, decimal_places=2)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True)
    settled_at = models.DateTimeField(null=True, blank=True)
    settlement_reference = models.CharField(max_length=100, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=(Q(order__isnull=False) & Q(reservation__isnull=True))
                | (Q(order__isnull=True) & Q(reservation__isnull=False)),
                name="commission_one_source",
            ),
        ]

    def __str__(self):
        return f"₹{self.amount} from {self.shop.name} ({self.status})"
