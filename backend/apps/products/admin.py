from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline

from .models import Product, ProductImage


class ProductImageInline(TabularInline):
    model = ProductImage
    extra = 0


@admin.register(Product)
class ProductAdmin(ModelAdmin):
    list_display = ["name", "shop", "category", "unit", "standard_price", "is_active"]
    list_filter = ["category", "unit", "is_active"]
    search_fields = ["name", "shop__name"]
    raw_id_fields = ["shop"]
    inlines = [ProductImageInline]
