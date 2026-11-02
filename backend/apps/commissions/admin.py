from django.contrib import admin, messages
from django.utils import timezone

from . import services
from .models import Commission, CommissionRule


@admin.register(CommissionRule)
class CommissionRuleAdmin(admin.ModelAdmin):
    list_display = ["__str__", "category", "rate_percent", "is_active"]
    list_editable = ["rate_percent", "is_active"]


@admin.register(Commission)
class CommissionAdmin(admin.ModelAdmin):
    list_display = ["shop", "order", "reservation", "transaction_amount", "amount", "status", "settled_at", "created_at"]
    list_filter = ["status", "shop__city"]
    search_fields = ["shop__name", "order__order_number", "reservation__reservation_number", "settlement_reference"]
    raw_id_fields = ["shop", "order", "reservation"]
    readonly_fields = ["transaction_amount", "amount"]
    date_hierarchy = "created_at"
    actions = ["settle"]

    @admin.action(description="Mark selected as settled (collected from merchant)")
    def settle(self, request, queryset):
        reference = f"ADMIN-{timezone.localdate():%Y%m%d}-{request.user.pk}"
        count = services.settle(queryset, request.user, reference)
        self.message_user(request, f"{count} commission(s) settled with reference {reference}.", messages.SUCCESS)
