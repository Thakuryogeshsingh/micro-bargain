from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models

from common.models import TimeStampedModel


class DailyOrder(TimeStampedModel):
    """A standing order: the same item from the same shop on chosen weekdays (milk, bread...). Paid to the shop monthly."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        CANCELLED = "cancelled", "Cancelled"

    class Slot(models.TextChoices):
        MORNING = "morning", "Morning"
        EVENING = "evening", "Evening"

    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="daily_orders")
    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="daily_orders")
    product = models.ForeignKey("products.Product", on_delete=models.PROTECT, related_name="daily_orders")
    quantity = models.DecimalField(max_digits=8, decimal_places=2, validators=[MinValueValidator(Decimal("0.25"))])
    price = models.DecimalField(max_digits=10, decimal_places=2, help_text="Per unit, fixed when subscribing")
    # Monday..Sunday as 7 characters of 1/0, e.g. "1111100" = weekdays only.
    weekdays = models.CharField(max_length=7, default="1111111", validators=[RegexValidator(r"^[01]{7}$")])
    slot = models.CharField(max_length=10, choices=Slot.choices, default=Slot.MORNING)
    address = models.ForeignKey("customers.Address", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    note = models.CharField(max_length=200, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ACTIVE, db_index=True)
    paused_until = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.customer} · {self.product} x{self.quantity}"

    def due_on(self, day):
        """Should the shop deliver on this date?"""
        if self.status != self.Status.ACTIVE and not (self.status == self.Status.PAUSED and self.paused_until and day > self.paused_until):
            return False
        return self.weekdays[day.weekday()] == "1" and day >= self.created_at.date()


class DailyDelivery(TimeStampedModel):
    class Status(models.TextChoices):
        DELIVERED = "delivered", "Delivered"
        SKIPPED = "skipped", "Skipped"

    daily = models.ForeignKey(DailyOrder, on_delete=models.CASCADE, related_name="deliveries")
    date = models.DateField()
    status = models.CharField(max_length=10, choices=Status.choices)
    quantity = models.DecimalField(max_digits=8, decimal_places=2)
    amount = models.DecimalField(max_digits=10, decimal_places=2)

    class Meta:
        ordering = ["-date"]
        constraints = [models.UniqueConstraint(fields=["daily", "date"], name="one_delivery_per_day")]
        verbose_name_plural = "daily deliveries"
