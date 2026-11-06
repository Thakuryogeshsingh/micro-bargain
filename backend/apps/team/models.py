from django.conf import settings
from django.db import models

from common.models import TimeStampedModel


class ShopStaff(TimeStampedModel):
    """Someone who works for a shop: a helper (handles orders and pickups) or a delivery person (own deliveries only)."""

    class Kind(models.TextChoices):
        HELPER = "helper", "Shop helper"
        DELIVERY = "delivery", "Delivery"

    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="staff")
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="staff_job")
    kind = models.CharField(max_length=10, choices=Kind.choices, default=Kind.HELPER)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name_plural = "shop staff"

    def __str__(self):
        return f"{self.user} ({self.get_kind_display()}) · {self.shop}"


def staff_job(user):
    """The active job of a staff user, or None."""
    job = getattr(user, "staff_job", None)
    return job if job is not None and job.is_active else None
