from django.contrib import admin
from unfold.admin import ModelAdmin
from common.admin_display import status_badge as badge

from .models import DailyDelivery, DailyOrder


@admin.register(DailyOrder)
class DailyOrderAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    list_display = ["customer", "shop", "product", "quantity", "weekdays", "slot", "status_badge", "created_at"]
    list_filter = ["status", "slot"]
    search_fields = ["customer__phone", "shop__name", "product__name"]
    raw_id_fields = ["customer", "shop", "product", "address"]


@admin.register(DailyDelivery)
class DailyDeliveryAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    list_display = ["daily", "date", "status_badge", "amount"]
    list_filter = ["status", "date"]
