from django.conf import settings
from django.db import models
from django.db.models import Q

from common.models import TimeStampedModel


class Inventory(TimeStampedModel):
    """Stock the shop has of a product, separate from the product master (doc section 9.3).

    Optional per product. When a product has an inventory row, a deal cannot offer more than the
    stock on hand, and every pickup/delivery deducts from it.
    """

    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="inventory")
    product = models.OneToOneField("products.Product", on_delete=models.CASCADE, related_name="inventory")
    quantity_on_hand = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    low_stock_threshold = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    class Meta:
        verbose_name_plural = "inventory"
        ordering = ["product__name"]
        constraints = [models.CheckConstraint(condition=Q(quantity_on_hand__gte=0), name="inventory_not_negative")]

    def __str__(self):
        return f"{self.product.name}: {self.quantity_on_hand} {self.product.unit}"

    @property
    def is_low(self):
        return self.quantity_on_hand <= self.low_stock_threshold


class InventoryMovement(models.Model):
    class Reason(models.TextChoices):
        RESTOCK = "restock", "Restock"
        SALE = "sale", "Sale"
        WASTAGE = "wastage", "Wastage / spoiled"
        ADJUSTMENT = "adjustment", "Stock count correction"

    inventory = models.ForeignKey(Inventory, on_delete=models.CASCADE, related_name="movements")
    change = models.DecimalField(max_digits=10, decimal_places=2)
    balance_after = models.DecimalField(max_digits=10, decimal_places=2)
    reason = models.CharField(max_length=12, choices=Reason.choices)
    reference = models.CharField(max_length=40, blank=True)  # reservation/order number for sales
    note = models.CharField(max_length=255, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"{self.change:+} {self.reason}"
