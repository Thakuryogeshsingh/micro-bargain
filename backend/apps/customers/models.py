from django.conf import settings
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

    class Meta:
        ordering = ["-is_default", "-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user"], condition=Q(is_default=True), name="one_default_address_per_user"),
        ]

    def __str__(self):
        return f"{self.label}: {self.address_line}, {self.city}"
