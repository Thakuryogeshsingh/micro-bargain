from django.contrib import admin
from unfold.admin import ModelAdmin

from .models import DailyDelivery, DailyOrder


@admin.register(DailyOrder)
class DailyOrderAdmin(ModelAdmin):
    list_display = ["customer", "shop", "product", "quantity", "weekdays", "slot", "status", "created_at"]
    list_filter = ["status", "slot"]
    search_fields = ["customer__phone", "shop__name", "product__name"]
    raw_id_fields = ["customer", "shop", "product", "address"]


@admin.register(DailyDelivery)
class DailyDeliveryAdmin(ModelAdmin):
    list_display = ["daily", "date", "status", "amount"]
    list_filter = ["status", "date"]
