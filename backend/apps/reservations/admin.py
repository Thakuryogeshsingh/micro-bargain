from django.contrib import admin
from unfold.admin import ModelAdmin
from common.admin_display import status_badge as badge
from unfold.contrib.filters.admin import RangeDateTimeFilter

from .models import DealReservation


@admin.register(DealReservation)
class DealReservationAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    list_filter_submit = True
    list_display = ["reservation_number", "customer", "shop", "deal", "quantity", "total_amount", "status_badge", "expires_at"]
    list_filter = ["status", "shop__city", ("created_at", RangeDateTimeFilter)]
    search_fields = ["reservation_number", "customer__phone", "shop__name"]
    raw_id_fields = ["customer", "deal", "shop"]
    readonly_fields = ["reservation_number", "pickup_code", "unit_price", "normal_unit_price", "total_amount",
                       "confirmed_at", "completed_at"]
    date_hierarchy = "created_at"
