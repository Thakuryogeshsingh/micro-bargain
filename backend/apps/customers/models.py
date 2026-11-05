from django.conf import settings
from django.core.validators import RegexValidator
from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel
from common.validators import pincode_validator


class CustomerProfile(TimeStampedModel):
    class SearchRadius(models.IntegerChoices):
        KM_1 = 1000, "1 km"
        KM_2 = 2000, "2 km"
        KM_5 = 5000, "5 km"
        KM_10 = 10000, "10 km"

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="customer_profile")
    search_radius_m = models.PositiveIntegerField(choices=SearchRadius.choices, default=SearchRadius.KM_2)
    notify_nearby_deals = models.BooleanField(default=True)
    notify_favorite_shops = models.BooleanField(default=True)
    notify_order_updates = models.BooleanField(default=True)
    preferred_categories = models.ManyToManyField("categories.Category", blank=True, related_name="+")
    referral_code = models.CharField(max_length=10, unique=True, null=True, blank=True)
    referred_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="referrals"
    )
    referral_rewarded_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Customer {self.user.phone}"


class Address(TimeStampedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="addresses")
    label = models.CharField(max_length=50, default="Home")
    address_line = models.CharField(max_length=255)
    landmark = models.CharField(max_length=120, blank=True)
    city = models.CharField(max_length=80)
    state = models.CharField(max_length=80)
    pincode = models.CharField(max_length=6, validators=[pincode_validator])
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    is_default = models.BooleanField(default=False)
    # Set when the address belongs to someone else (ordering for family/friends).
    contact_name = models.CharField(max_length=120, blank=True)
    contact_phone = models.CharField(max_length=10, blank=True, validators=[RegexValidator(r"^[6-9]\d{9}$", "Enter a 10-digit mobile number")])

    class Meta:
        ordering = ["-is_default", "-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user"], condition=Q(is_default=True), name="one_default_address_per_user"),
        ]

    def __str__(self):
        return f"{self.label}: {self.address_line}, {self.city}"


class PlusMembership(TimeStampedModel):
    """Bargain Plus: a paid customer membership (free delivery + extra discount on orders)."""

    class Status(models.TextChoices):
        PENDING_PAYMENT = "pending_payment", "Waiting for payment"
        ACTIVE = "active", "Active"
        EXPIRED = "expired", "Expired"
        CANCELLED = "cancelled", "Cancelled"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="plus_memberships")
    amount = models.DecimalField(max_digits=8, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING_PAYMENT, db_index=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Plus {self.user.phone} ({self.status})"



class WalletEntry(models.Model):
    """Money in the customer's wallet: cashback credits, and debits when used on an order."""

    class Kind(models.TextChoices):
        CASHBACK = "cashback", "Cashback"
        USED = "used", "Used on an order"
        RETURNED = "returned", "Returned (order cancelled)"
        REFUND = "refund", "Refund (quality complaint)"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wallet_entries")
    kind = models.CharField(max_length=10, choices=Kind.choices)
    amount = models.DecimalField(max_digits=10, decimal_places=2, help_text="Positive = credit, negative = debit")
    reference = models.CharField(max_length=20, blank=True)  # order / reservation number
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"{self.user.phone} {self.amount:+}"
