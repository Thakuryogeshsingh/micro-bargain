from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline
from common.admin_display import thumbnail

from .models import Product, ProductImage


class ProductImageInline(TabularInline):
    model = ProductImage
    extra = 0


@admin.register(Product)
class ProductAdmin(ModelAdmin):
    photo = thumbnail(lambda p: next(iter(p.images.all()), None) and next(iter(p.images.all())).image)
    list_display = [
        "photo","name", "shop", "category", "unit", "standard_price", "is_active"]
    list_filter = ["category", "unit", "is_active"]
    search_fields = ["name", "shop__name"]
    raw_id_fields = ["shop"]
    inlines = [ProductImageInline]
