from django.contrib import admin
from unfold.admin import ModelAdmin

from .models import ShopStaff


@admin.register(ShopStaff)
class ShopStaffAdmin(ModelAdmin):
    list_display = ["user", "shop", "kind", "is_active", "created_at"]
    list_filter = ["kind", "is_active"]
    search_fields = ["user__phone", "user__name", "shop__name"]
    raw_id_fields = ["user", "shop"]
