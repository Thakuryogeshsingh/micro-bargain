from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline

from .models import Inventory, InventoryMovement


class MovementInline(TabularInline):
    model = InventoryMovement
    extra = 0
    can_delete = False
    readonly_fields = ["change", "balance_after", "reason", "reference", "note", "created_by", "created_at"]

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Inventory)
class InventoryAdmin(ModelAdmin):
    list_display = ["product", "shop", "quantity_on_hand", "low_stock_threshold", "updated_at"]
    search_fields = ["product__name", "shop__name"]
    raw_id_fields = ["shop", "product"]
    readonly_fields = ["quantity_on_hand"]  # change stock through movements only
    inlines = [MovementInline]
