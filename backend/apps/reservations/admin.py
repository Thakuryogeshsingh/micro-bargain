from django.contrib import admin

from .models import DealReservation


@admin.register(DealReservation)
class DealReservationAdmin(admin.ModelAdmin):
    list_display = ["reservation_number", "customer", "shop", "deal", "quantity", "total_amount", "status", "expires_at"]
    list_filter = ["status", "shop__city"]
    search_fields = ["reservation_number", "customer__phone", "shop__name"]
    raw_id_fields = ["customer", "deal", "shop"]
    readonly_fields = ["reservation_number", "pickup_code", "unit_price", "normal_unit_price", "total_amount",
                       "confirmed_at", "completed_at"]
    date_hierarchy = "created_at"
