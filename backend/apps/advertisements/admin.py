from django.contrib import admin, messages
from unfold.admin import ModelAdmin

from . import services
from .models import Advertisement


@admin.register(Advertisement)
class AdvertisementAdmin(ModelAdmin):
    list_display = ["shop", "placement", "deal", "title", "price", "status", "starts_at", "ends_at", "impressions", "clicks"]
    list_filter = ["placement", "status"]
    search_fields = ["shop__name", "title"]
    raw_id_fields = ["shop", "deal"]
    readonly_fields = ["status", "price", "starts_at", "ends_at", "impressions", "clicks"]
    actions = ["reject"]

    @admin.action(description="Reject / take down selected promotions (paid ones are refunded)")
    def reject(self, request, queryset):
        for ad in queryset:
            try:
                services.reject(ad, request.user, "Does not follow promotion guidelines.")
            except Exception as exc:
                self.message_user(request, f"Ad {ad.pk}: {exc}", messages.ERROR)
        self.message_user(request, "Done.", messages.INFO)
