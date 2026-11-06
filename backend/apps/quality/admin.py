from django.contrib import admin, messages
from django.utils.html import format_html
from unfold.admin import ModelAdmin
from common.admin_display import status_badge as badge
from unfold.contrib.filters.admin import RangeDateTimeFilter

from common.exceptions import BusinessRuleError

from . import services
from .models import QualityComplaint


@admin.register(QualityComplaint)
class QualityComplaintAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    list_filter_submit = True
    list_display = ["id", "shop", "customer", "reason", "amount_paid", "status_badge", "refund_amount", "created_at"]
    list_filter = ["status", "reason", "shop__city", ("created_at", RangeDateTimeFilter)]
    search_fields = ["shop__name", "customer__phone", "order__order_number", "reservation__reservation_number"]
    raw_id_fields = ["customer", "shop", "reservation", "order", "resolved_by"]
    readonly_fields = ["photo_preview", "amount_paid", "refund_amount", "resolved_at", "resolved_by"]
    actions = ["refund_full", "reject"]

    @admin.display(description="Photo")
    def photo_preview(self, obj):
        return format_html('<a href="{0}" target="_blank"><img src="{0}" style="max-height:240px"></a>', obj.photo.url) if obj.photo else "-"

    def _decide(self, request, queryset, refund):
        done = 0
        for complaint in queryset:
            try:
                services.admin_decide(complaint, request.user, refund=refund, note="Decided by the Micro Bargain team")
                done += 1
            except BusinessRuleError as error:
                self.message_user(request, f"#{complaint.id}: {error}", messages.WARNING)
        self.message_user(request, f"{done} complaint(s) updated.", messages.SUCCESS)

    @admin.action(description="Refund full amount to the customer's wallet")
    def refund_full(self, request, queryset):
        self._decide(request, queryset, True)

    @admin.action(description="Reject (complaint not valid)")
    def reject(self, request, queryset):
        self._decide(request, queryset, False)
