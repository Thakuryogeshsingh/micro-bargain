from django.contrib import admin

from .models import DailyDelivery, DailyOrder


@admin.register(DailyOrder)
class DailyOrderAdmin(admin.ModelAdmin):
    list_display = ["customer", "shop", "product", "quantity", "weekdays", "slot", "status", "created_at"]
    list_filter = ["status", "slot"]
    search_fields = ["customer__phone", "shop__name", "product__name"]
    raw_id_fields = ["customer", "shop", "product", "address"]


@admin.register(DailyDelivery)
class DailyDeliveryAdmin(admin.ModelAdmin):
    list_display = ["daily", "date", "status", "amount"]
    list_filter = ["status", "date"]
