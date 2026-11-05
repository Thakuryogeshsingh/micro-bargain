from django.conf import settings
from django.db import models

from common.models import TimeStampedModel
from common.validators import validate_image_file


class QualityComplaint(TimeStampedModel):
    """A customer says the goods were stale, damaged, wrong or short. The shop refunds (to the wallet) or disputes."""

    class Reason(models.TextChoices):
        STALE = "stale", "Stale / rotten"
        DAMAGED = "damaged", "Damaged"
        EXPIRED = "expired", "Expired"
        WRONG_ITEM = "wrong_item", "Wrong item"
        SHORT = "short", "Less quantity"
        OTHER = "other", "Other"

    class Status(models.TextChoices):
        OPEN = "open", "Waiting for the shop"
        REFUNDED = "refunded", "Refunded"
        DISPUTED = "disputed", "Disputed (admin will decide)"
        REJECTED = "rejected", "Rejected"

    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="quality_complaints")
    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="quality_complaints")
    reservation = models.OneToOneField(
        "reservations.DealReservation", null=True, blank=True, on_delete=models.CASCADE, related_name="quality_complaint"
    )
    order = models.OneToOneField("orders.Order", null=True, blank=True, on_delete=models.CASCADE, related_name="quality_complaint")
    reason = models.CharField(max_length=15, choices=Reason.choices)
    description = models.TextField(blank=True, max_length=1000)
    photo = models.ImageField(upload_to="complaints/", validators=[validate_image_file])
    amount_paid = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.OPEN, db_index=True)
    refund_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    shop_note = models.CharField(max_length=500, blank=True)
    admin_note = models.CharField(max_length=500, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"#{self.id} {self.shop} — {self.get_reason_display()}"

    @property
    def reference(self):
        source = self.reservation or self.order
        return source.reservation_number if self.reservation_id else source.order_number
