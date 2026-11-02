from django.contrib import admin

from .models import MerchantSubscription, Plan


@admin.register(Plan)
class PlanAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "price_monthly", "max_active_deals", "analytics", "featured_listing", "is_active"]
    list_editable = ["price_monthly", "max_active_deals", "is_active"]


@admin.register(MerchantSubscription)
class MerchantSubscriptionAdmin(admin.ModelAdmin):
    list_display = ["merchant", "plan", "amount", "status", "starts_at", "ends_at"]
    list_filter = ["status", "plan"]
    search_fields = ["merchant__owner_name", "merchant__user__phone"]
    raw_id_fields = ["merchant"]
