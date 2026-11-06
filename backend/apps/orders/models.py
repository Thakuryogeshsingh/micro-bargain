from django.conf import settings
from django.db import models
from django.db.models import F, Q

from apps.products.models import Product
from common.models import TimeStampedModel


class Coupon(TimeStampedModel):
    class DiscountType(models.TextChoices):
        PERCENT = "percent", "Percent"
        FLAT = "flat", "Flat ₹"

    code = models.CharField(max_length=20, unique=True)  # stored upper-case
    description = models.CharField(max_length=255, blank=True)
    shop = models.ForeignKey(
        "shops.Shop", null=True, blank=True, on_delete=models.CASCADE, related_name="coupons",
        help_text="Empty = valid at every shop (platform coupon)",
    )
    discount_type = models.CharField(max_length=10, choices=DiscountType.choices)
    value = models.DecimalField(max_digits=8, decimal_places=2)
    max_discount = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    min_order_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    valid_from = models.DateTimeField()
    valid_until = models.DateTimeField()
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE, related_name="personal_coupons",
        help_text="Set for a personal coupon (e.g. referral reward); empty = anyone can use it",
    )
    first_order_only = models.BooleanField(default=False)
    usage_limit = models.PositiveIntegerField(null=True, blank=True, help_text="Total uses; empty = unlimited")
    per_customer_limit = models.PositiveSmallIntegerField(default=1)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(value__gt=0), name="coupon_value_positive"),
            models.CheckConstraint(
                condition=~Q(discount_type="percent") | Q(value__lte=100), name="coupon_percent_max_100"
            ),
            models.CheckConstraint(condition=Q(valid_until__gt=F("valid_from")), name="coupon_valid_window"),
        ]

    def __str__(self):
        return self.code

    def save(self, *args, **kwargs):
        self.code = self.code.strip().upper()
        super().save(*args, **kwargs)


class Order(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING_PAYMENT = "pending_payment", "Waiting for payment"
        PENDING = "pending", "Waiting for shop"
        CONFIRMED = "confirmed", "Confirmed / preparing"
        READY = "ready", "Ready for pickup"
        OUT_FOR_DELIVERY = "out_for_delivery", "Out for delivery"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        REFUNDED = "refunded", "Refunded"

    # Stock is held for these statuses.
    OPEN_STATUSES = (Status.PENDING_PAYMENT, Status.PENDING, Status.CONFIRMED, Status.READY, Status.OUT_FOR_DELIVERY)

    class Fulfilment(models.TextChoices):
        PICKUP = "pickup", "Pickup"
        DELIVERY = "delivery", "Home delivery"

    class PaymentMethod(models.TextChoices):
        ONLINE = "online", "UPI / card / net banking"
        CASH = "cash", "Cash at shop / on delivery"

    class PaymentStatus(models.TextChoices):
        UNPAID = "unpaid", "Unpaid"
        PAID = "paid", "Paid"
        REFUNDED = "refunded", "Refunded"
        PARTIALLY_REFUNDED = "partially_refunded", "Partially refunded"

    order_number = models.CharField(max_length=12, unique=True)
    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="orders")
    shop = models.ForeignKey("shops.Shop", on_delete=models.PROTECT, related_name="orders")
    fulfilment = models.CharField(max_length=10, choices=Fulfilment.choices, default=Fulfilment.PICKUP)
    status = models.CharField(max_length=20, choices=Status.choices, db_index=True)
    payment_method = models.CharField(max_length=10, choices=PaymentMethod.choices)
    payment_status = models.CharField(max_length=20, choices=PaymentStatus.choices, default=PaymentStatus.UNPAID)

    # Delivery address is copied so later edits to the address book do not change past orders.
    delivery_address = models.CharField(max_length=400, blank=True)
    recipient_name = models.CharField(max_length=120, blank=True)  # someone else receives the delivery
    recipient_phone = models.CharField(max_length=10, blank=True)
    delivery_partner = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="deliveries")
    rider_latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    rider_longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    rider_updated_at = models.DateTimeField(null=True, blank=True)
    delivery_latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    delivery_longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    subtotal = models.DecimalField(max_digits=12, decimal_places=2)
    savings = models.DecimalField(max_digits=12, decimal_places=2, default=0)  # vs normal price
    coupon = models.ForeignKey(Coupon, null=True, blank=True, on_delete=models.PROTECT, related_name="orders")
    coupon_discount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    plus_discount = models.DecimalField(max_digits=10, decimal_places=2, default=0)  # Bargain Plus members
    wallet_used = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    delivery_fee = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)
    refunded_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    pickup_code = models.CharField(max_length=4)  # also used as the delivery OTP
    note = models.CharField(max_length=255, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)  # deadline for payment / shop acceptance
    confirmed_at = models.DateTimeField(null=True, blank=True)
    ready_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancel_reason = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status", "expires_at"]),
            models.Index(fields=["shop", "status"]),
            models.Index(fields=["customer", "status"]),
        ]
        constraints = [
            models.CheckConstraint(condition=Q(total_amount__gte=0), name="order_total_not_negative"),
            models.CheckConstraint(condition=Q(refunded_amount__lte=F("total_amount")), name="order_refund_within_total"),
        ]

    def __str__(self):
        return f"{self.order_number} ({self.status})"


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    deal = models.ForeignKey("deals.Deal", on_delete=models.PROTECT, related_name="order_items")
    product_name = models.CharField(max_length=150)
    unit = models.CharField(max_length=10, choices=Product.Unit.choices)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    normal_unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    line_total = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(quantity__gt=0), name="order_item_quantity_positive"),
            models.UniqueConstraint(fields=["order", "deal"], name="one_line_per_deal"),
        ]

    def __str__(self):
        return f"{self.quantity} {self.unit} {self.product_name}"
