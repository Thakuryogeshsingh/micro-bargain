from django.conf import settings
from django.core.validators import RegexValidator
from django.db import models

from common.models import TimeStampedModel


class MerchantProfile(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending verification"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        SUSPENDED = "suspended", "Suspended"

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="merchant_profile")
    owner_name = models.CharField(max_length=150)
    business_category = models.ForeignKey("categories.Category", on_delete=models.PROTECT, related_name="+")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    rejection_reason = models.TextField(blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    # Payouts (onboarding step 4): a UPI ID, or a bank account.
    upi_id = models.CharField(max_length=60, blank=True, validators=[RegexValidator(r"^[\w.\-]{2,}@[A-Za-z]{2,}$", "Enter a valid UPI ID, e.g. name@okaxis")])
    bank_account_name = models.CharField(max_length=120, blank=True)
    bank_account_number = models.CharField(max_length=18, blank=True, validators=[RegexValidator(r"^\d{9,18}$", "9 to 18 digits")])
    bank_ifsc = models.CharField(max_length=11, blank=True, validators=[RegexValidator(r"^[A-Z]{4}0[A-Z0-9]{6}$", "Enter a valid IFSC, e.g. SBIN0001234")])
    onboarding_submitted_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.owner_name} ({self.user.phone})"

    @property
    def is_approved(self):
        return self.status == self.Status.APPROVED
