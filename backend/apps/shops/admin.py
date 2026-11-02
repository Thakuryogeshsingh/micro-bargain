from django.contrib import messages
from django.contrib.gis import admin

from . import services
from .models import FavoriteShop, Shop, ShopDocument


class ShopDocumentInline(admin.TabularInline):
    model = ShopDocument
    extra = 0
    fields = ["doc_type", "file", "status", "remarks", "created_at"]
    readonly_fields = ["created_at"]


@admin.register(Shop)
class ShopAdmin(admin.GISModelAdmin):
    list_display = ["name", "merchant", "category", "city", "status", "is_temporarily_closed", "created_at"]
    list_filter = ["status", "city", "category", "offers_delivery"]
    search_fields = ["name", "merchant__owner_name", "merchant__user__phone", "pincode"]
    raw_id_fields = ["merchant"]
    readonly_fields = ["reviewed_at", "rating_avg", "rating_count"]
    inlines = [ShopDocumentInline]
    actions = ["approve", "reject"]

    @admin.action(description="Approve selected shops (also approves a pending merchant)")
    def approve(self, request, queryset):
        for shop in queryset.select_related("merchant"):
            services.review_shop(shop, request.user, approve=True)
        self.message_user(request, f"{queryset.count()} shop(s) approved.", messages.SUCCESS)

    @admin.action(description="Reject selected shops")
    def reject(self, request, queryset):
        for shop in queryset.select_related("merchant"):
            services.review_shop(shop, request.user, approve=False, reason="Rejected by admin.")
        self.message_user(request, f"{queryset.count()} shop(s) rejected.", messages.WARNING)


@admin.register(FavoriteShop)
class FavoriteShopAdmin(admin.ModelAdmin):
    list_display = ["user", "shop", "created_at"]
    raw_id_fields = ["user", "shop"]
