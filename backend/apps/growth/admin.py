from django.contrib import admin, messages
from unfold.admin import ModelAdmin, TabularInline
from unfold.decorators import display

from common.exceptions import BusinessRuleError

from . import services
from .models import Broadcast, Campaign, GroupDeal, GroupMember, LoyaltyAccount, PriceAlert


@admin.register(Broadcast)
class BroadcastAdmin(ModelAdmin):
    list_display = ["title", "audience", "city", "send_at", "sent_badge", "sent_count", "created_at"]
    list_filter = ["audience"]
    search_fields = ["title", "body"]
    readonly_fields = ["sent_at", "sent_count"]
    actions = ["send_now"]

    @display(description="Sent", label={"sent": "success", "waiting": "warning"})
    def sent_badge(self, obj):
        return ("sent", "Sent") if obj.sent_at else ("waiting", "Not sent")

    @admin.action(description="Send now to everyone in the audience")
    def send_now(self, request, queryset):
        for broadcast in queryset:
            try:
                count = services.send_broadcast(broadcast)
                self.message_user(request, f"'{broadcast.title}' sent to {count} people.", messages.SUCCESS)
            except BusinessRuleError as error:
                self.message_user(request, f"'{broadcast.title}': {error}", messages.WARNING)


@admin.register(Campaign)
class CampaignAdmin(ModelAdmin):
    list_display = ["name", "title", "coupon", "starts_at", "ends_at", "live_badge", "announce"]
    raw_id_fields = ["coupon"]
    readonly_fields = ["announced_at"]

    @display(description="Now", label={"live": "success", "soon": "info", "over": "danger"})
    def live_badge(self, obj):
        from django.utils import timezone

        now = timezone.now()
        if obj.starts_at <= now < obj.ends_at:
            return "live", "Live"
        return ("soon", "Upcoming") if now < obj.starts_at else ("over", "Ended")


class MemberInline(TabularInline):
    model = GroupMember
    extra = 0
    readonly_fields = ["user", "rewarded_at", "created_at"]


@admin.register(GroupDeal)
class GroupDealAdmin(ModelAdmin):
    list_display = ["deal", "target", "extra_percent", "unlocked_at", "created_at"]
    raw_id_fields = ["deal"]
    inlines = [MemberInline]


@admin.register(PriceAlert)
class PriceAlertAdmin(ModelAdmin):
    list_display = ["user", "query", "max_price", "is_active", "last_notified_at", "created_at"]
    search_fields = ["user__phone", "query"]
    raw_id_fields = ["user"]
    exclude = ["notified_deals"]


@admin.register(LoyaltyAccount)
class LoyaltyAccountAdmin(ModelAdmin):
    list_display = ["user", "points", "streak_days", "best_streak", "last_purchase_date"]
    search_fields = ["user__phone"]
    raw_id_fields = ["user"]
