from django.contrib import admin, messages
from unfold.admin import ModelAdmin

from . import services
from .models import MerchantProfile


@admin.register(MerchantProfile)
class MerchantProfileAdmin(ModelAdmin):
    list_display = ["owner_name", "user", "business_category", "status", "onboarding_submitted_at", "created_at"]
    list_filter = ["status", "business_category"]
    search_fields = ["owner_name", "user__phone"]
    raw_id_fields = ["user"]
    readonly_fields = ["reviewed_at", "reviewed_by"]
    actions = ["approve", "reject"]

    @admin.action(description="Approve selected merchants")
    def approve(self, request, queryset):
        from apps.shops.services import review_shop

        for profile in queryset:
            pending = list(profile.shops.filter(status="pending"))
            for shop in pending:  # approves the merchant too, and tells them
                review_shop(shop, request.user, approve=True)
            if not pending:
                services.review_merchant(profile, request.user, approve=True)
        self.message_user(request, f"{queryset.count()} merchant(s) approved.", messages.SUCCESS)

    @admin.action(description="Reject selected merchants")
    def reject(self, request, queryset):
        for profile in queryset:
            services.review_merchant(profile, request.user, approve=False, reason="Rejected by admin.")
        self.message_user(request, f"{queryset.count()} merchant(s) rejected.", messages.WARNING)
