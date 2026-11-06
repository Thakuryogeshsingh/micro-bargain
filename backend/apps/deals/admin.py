from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline
from common.admin_display import status_badge as badge, thumbnail

from .models import Deal, DealChangeLog


class DealChangeLogInline(TabularInline):
    model = DealChangeLog
    extra = 0
    can_delete = False
    readonly_fields = ["field", "old_value", "new_value", "changed_by", "created_at"]

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Deal)
class DealAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    photo = thumbnail(lambda d: d.image or (next(iter(d.product.images.all()), None) and next(iter(d.product.images.all())).image))
    list_display = [
        "photo",
        "product", "shop", "offer_price", "normal_price", "discount_percent",
        "quantity_total", "quantity_reserved", "quantity_sold", "status_badge", "expires_at",
    ]
    list_filter = ["status", "fulfilment", "product__category", "shop__city"]
    search_fields = ["product__name", "shop__name"]
    raw_id_fields = ["shop", "product"]
    readonly_fields = ["discount_percent", "quantity_reserved", "quantity_sold", "published_at"]
    date_hierarchy = "created_at"
    inlines = [DealChangeLogInline]
