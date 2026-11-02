from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel
from common.validators import validate_image_file


class Advertisement(TimeStampedModel):
    """Paid promotion (doc 13.3 / 13.4): a featured deal shown first in search, or a home-screen banner."""

    class Placement(models.TextChoices):
        FEATURED_DEAL = "featured_deal", "Featured deal"
        HOME_BANNER = "home_banner", "Home screen banner"

    class Status(models.TextChoices):
        PENDING_PAYMENT = "pending_payment", "Waiting for payment"
        ACTIVE = "active", "Running"
        EXPIRED = "expired", "Finished"
        REJECTED = "rejected", "Rejected by admin"
        CANCELLED = "cancelled", "Cancelled"

    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="advertisements")
    deal = models.ForeignKey("deals.Deal", null=True, blank=True, on_delete=models.CASCADE, related_name="advertisements")
    placement = models.CharField(max_length=15, choices=Placement.choices)
    title = models.CharField(max_length=80, blank=True)
    banner_image = models.ImageField(upload_to="ads/", blank=True, validators=[validate_image_file])
    radius_m = models.PositiveIntegerField(default=5000)  # banners show to customers within this distance
    days = models.PositiveSmallIntegerField()
    price = models.DecimalField(max_digits=8, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING_PAYMENT, db_index=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=255, blank=True)
    impressions = models.PositiveIntegerField(default=0)
    clicks = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["placement", "status", "ends_at"])]
        constraints = [
            models.CheckConstraint(
                condition=~Q(placement="featured_deal") | Q(deal__isnull=False), name="featured_ad_needs_deal"
            ),
        ]

    def __str__(self):
        return f"{self.get_placement_display()} for {self.shop.name} ({self.status})"
