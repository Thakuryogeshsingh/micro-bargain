from decimal import Decimal

from django.core.validators import MinValueValidator
from django.db import models

from common.models import TimeStampedModel
from common.validators import validate_image_file


class Product(TimeStampedModel):
    class Unit(models.TextChoices):
        KG = "kg", "KG"
        GRAM = "g", "Gram"
        PIECE = "piece", "Piece"
        PACKET = "packet", "Packet"
        LITRE = "litre", "Litre"
        DOZEN = "dozen", "Dozen"
        BOX = "box", "Box"

    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="products")
    category = models.ForeignKey("categories.Category", on_delete=models.PROTECT, related_name="products")
    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    unit = models.CharField(max_length=10, choices=Unit.choices)
    standard_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))])
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        indexes = [models.Index(fields=["shop", "is_active"])]

    def __str__(self):
        return f"{self.name} ({self.get_unit_display()})"


class ProductImage(TimeStampedModel):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to="products/", validators=[validate_image_file])
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "id"]

    def __str__(self):
        return f"Image {self.pk} of {self.product.name}"
