from django.contrib import admin, messages

from . import services
from .models import Payment, Refund, WebhookEvent


class ReadOnlyAdmin(admin.ModelAdmin):
    """Money records are written by the payment flow only."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Payment)
class PaymentAdmin(ReadOnlyAdmin):
    list_display = ["id", "user", "purpose", "amount", "status", "method", "gateway_order_id", "paid_at", "created_at"]
    list_filter = ["status", "purpose", "method"]
    search_fields = ["user__phone", "gateway_order_id", "gateway_payment_id", "order__order_number"]
    date_hierarchy = "created_at"


@admin.register(Refund)
class RefundAdmin(ReadOnlyAdmin):
    list_display = ["id", "payment", "amount", "status", "reason", "gateway_refund_id", "error", "created_at"]
    list_filter = ["status"]
    search_fields = ["payment__gateway_payment_id", "gateway_refund_id", "payment__order__order_number"]
    actions = ["retry"]

    @admin.action(description="Retry selected failed refunds")
    def retry(self, request, queryset):
        for refund in queryset.filter(status=Refund.Status.FAILED, gateway_refund_id=""):
            services.process_refund(refund.id)
        self.message_user(request, "Retried. Check the status column.", messages.INFO)


@admin.register(WebhookEvent)
class WebhookEventAdmin(ReadOnlyAdmin):
    list_display = ["event", "event_id", "received_at"]
    list_filter = ["event"]
    search_fields = ["event_id"]
