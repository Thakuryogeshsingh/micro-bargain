from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models

from common.models import TimeStampedModel


class KhataCustomer(TimeStampedModel):
    """Someone the shop gives goods on credit (udhaar). Not necessarily an app user."""

    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="khata_customers")
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=10, blank=True)
    note = models.CharField(max_length=200, blank=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.shop})"


class KhataEntry(TimeStampedModel):
    class Kind(models.TextChoices):
        CREDIT = "credit", "Given on credit"
        PAYMENT = "payment", "Payment received"

    customer = models.ForeignKey(KhataCustomer, on_delete=models.CASCADE, related_name="entries")
    kind = models.CharField(max_length=10, choices=Kind.choices)
    amount = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(1)])
    note = models.CharField(max_length=200, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["-created_at", "-id"]
        verbose_name_plural = "khata entries"
