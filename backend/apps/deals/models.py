from django.conf import settings
from django.db import models
from django.db.models import F, Q
from django.utils import timezone

from apps.products.models import Product
from common.models import TimeStampedModel
from common.utils import discount_percentage
from common.validators import validate_image_file


class Deal(TimeStampedModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        SOLD_OUT = "sold_out", "Sold out"
        EXPIRED = "expired", "Expired"
        ENDED = "ended", "Ended by merchant"

    class Fulfilment(models.TextChoices):
        PICKUP = "pickup", "Pickup"
        DELIVERY = "delivery", "Delivery"
        BOTH = "both", "Pickup or delivery"

    FINAL_STATUSES = (Status.EXPIRED, Status.ENDED)

    shop = models.ForeignKey("shops.Shop", on_delete=models.PROTECT, related_name="deals")
    product = models.ForeignKey("products.Product", on_delete=models.PROTECT, related_name="deals")
    description = models.TextField(blank=True)
    image = models.ImageField(upload_to="deals/", blank=True, validators=[validate_image_file])
    unit = models.CharField(max_length=10, choices=Product.Unit.choices)

    normal_price = models.DecimalField(max_digits=10, decimal_places=2)
    offer_price = models.DecimalField(max_digits=10, decimal_places=2)
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2, editable=False, db_index=True)

    # Stock is tracked on the deal itself. available = total - reserved - sold.
    quantity_total = models.DecimalField(max_digits=10, decimal_places=2)
    quantity_reserved = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    quantity_sold = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    starts_at = models.DateTimeField()
    expires_at = models.DateTimeField()
    fulfilment = models.CharField(max_length=10, choices=Fulfilment.choices, default=Fulfilment.PICKUP)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.DRAFT)
    published_at = models.DateTimeField(null=True, blank=True)
    view_count = models.PositiveIntegerField(default=0, editable=False)  # customer detail views, for reports

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status", "expires_at"]),
            models.Index(fields=["shop", "status"]),
        ]
        # Last line of defence: the database itself refuses overbooking and nonsense prices.
        constraints = [
            models.CheckConstraint(
                condition=Q(offer_price__gt=0) & Q(offer_price__lt=F("normal_price")),
                name="deal_offer_below_normal_price",
            ),
            models.CheckConstraint(
                condition=Q(quantity_reserved__gte=0) & Q(quantity_sold__gte=0) & Q(quantity_total__gt=0),
                name="deal_quantities_non_negative",
            ),
            models.CheckConstraint(
                condition=Q(quantity_total__gte=F("quantity_reserved") + F("quantity_sold")),
                name="deal_no_overbooking",
            ),
            models.CheckConstraint(condition=Q(expires_at__gt=F("starts_at")), name="deal_expires_after_start"),
        ]

    def __str__(self):
        return f"{self.product.name} ₹{self.offer_price}/{self.unit} at {self.shop.name}"

    def save(self, *args, **kwargs):
        self.discount_percent = discount_percentage(self.normal_price, self.offer_price)
        update_fields = kwargs.get("update_fields")
        if update_fields is not None and {"normal_price", "offer_price"} & set(update_fields):
            kwargs["update_fields"] = {*update_fields, "discount_percent"}
        super().save(*args, **kwargs)

    @property
    def quantity_available(self):
        return self.quantity_total - self.quantity_reserved - self.quantity_sold

    @property
    def is_live(self):
        now = timezone.now()
        return (
            self.status == self.Status.ACTIVE
            and self.starts_at <= now < self.expires_at
            and self.quantity_available > 0
            and self.shop.is_live
        )


class DealChangeLog(models.Model):
    """Audit trail for price, stock and status changes (doc section 6.5)."""

    deal = models.ForeignKey(Deal, on_delete=models.CASCADE, related_name="change_logs")
    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    field = models.CharField(max_length=40)
    old_value = models.CharField(max_length=100, blank=True)
    new_value = models.CharField(max_length=100, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Deal {self.deal_id}: {self.field} {self.old_value} → {self.new_value}"
