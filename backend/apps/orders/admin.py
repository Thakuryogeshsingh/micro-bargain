from django.contrib import admin, messages
from unfold.admin import ModelAdmin, TabularInline
from common.admin_display import status_badge as badge
from unfold.contrib.filters.admin import RangeDateTimeFilter

from . import services
from .models import Coupon, Order, OrderItem


class OrderItemInline(TabularInline):
    model = OrderItem
    extra = 0
    can_delete = False
    readonly_fields = ["deal", "product_name", "unit", "quantity", "unit_price", "normal_unit_price", "line_total"]

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Order)
class OrderAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    payment_badge = badge("payment_status", "Payment")
    list_filter_submit = True
    list_display = ["order_number", "shop", "customer", "status_badge", "fulfilment", "payment_method", "payment_badge",
                    "total_amount", "created_at"]
    list_filter = ["status", "fulfilment", "payment_method", "payment_status", "shop__city", ("created_at", RangeDateTimeFilter)]
    search_fields = ["order_number", "customer__phone", "shop__name"]
    raw_id_fields = ["customer", "shop", "coupon"]
    date_hierarchy = "created_at"
    inlines = [OrderItemInline]
    actions = ["full_refund"]

    # Money and status change only through services (stock, refunds and commission stay consistent).
    def get_readonly_fields(self, request, obj=None):
        return [f.name for f in self.model._meta.fields]

    @admin.action(description="Fully refund selected completed online orders")
    def full_refund(self, request, queryset):
        done = 0
        for order in queryset:
            try:
                services.refund_completed_order(
                    order, order.total_amount - order.refunded_amount, "Refunded by admin", request.user
                )
                done += 1
            except Exception as exc:  # report and continue with the rest
                self.message_user(request, f"{order.order_number}: {exc}", messages.ERROR)
        if done:
            self.message_user(request, f"{done} order(s) refunded.", messages.SUCCESS)


@admin.register(Coupon)
class CouponAdmin(ModelAdmin):
    list_display = ["code", "shop", "discount_type", "value", "max_discount", "min_order_amount", "valid_until", "is_active"]
    list_filter = ["is_active", "discount_type"]
    search_fields = ["code", "description"]
    raw_id_fields = ["shop"]
