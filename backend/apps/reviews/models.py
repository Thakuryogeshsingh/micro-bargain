from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel
from common.validators import validate_image_file


class Review(TimeStampedModel):
    """A customer's rating of a shop after a completed pickup or order. One review per transaction."""

    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reviews")
    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="reviews")
    reservation = models.OneToOneField(
        "reservations.DealReservation", null=True, blank=True, on_delete=models.CASCADE, related_name="review"
    )
    order = models.OneToOneField("orders.Order", null=True, blank=True, on_delete=models.CASCADE, related_name="review")
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    comment = models.TextField(blank=True, max_length=1000)
    photo = models.ImageField(upload_to="reviews/", blank=True, validators=[validate_image_file])
    merchant_reply = models.TextField(blank=True, max_length=1000)
    replied_at = models.DateTimeField(null=True, blank=True)
    is_hidden = models.BooleanField(default=False, help_text="Hidden by admin (abusive or fake)")

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["shop", "is_hidden"])]
        constraints = [
            models.CheckConstraint(condition=Q(rating__gte=1) & Q(rating__lte=5), name="review_rating_1_to_5"),
            models.CheckConstraint(
                condition=(Q(order__isnull=False) & Q(reservation__isnull=True))
                | (Q(order__isnull=True) & Q(reservation__isnull=False)),
                name="review_one_source",
            ),
        ]

    def __str__(self):
        return f"{self.rating}★ for {self.shop.name}"
