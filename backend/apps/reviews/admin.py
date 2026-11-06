from django.contrib import admin, messages
from unfold.admin import ModelAdmin

from . import services
from .models import Review


@admin.register(Review)
class ReviewAdmin(ModelAdmin):
    list_display = ["shop", "customer", "rating", "comment", "is_hidden", "created_at"]
    list_filter = ["rating", "is_hidden"]
    search_fields = ["shop__name", "customer__phone", "comment"]
    raw_id_fields = ["customer", "shop", "reservation", "order"]
    readonly_fields = ["is_hidden"]  # use the actions so the shop rating is recalculated
    actions = ["hide", "show"]

    @admin.action(description="Hide selected reviews (abusive / fake)")
    def hide(self, request, queryset):
        for review in queryset:
            services.set_hidden(review, True, request.user)
        self.message_user(request, f"{queryset.count()} review(s) hidden.", messages.SUCCESS)

    @admin.action(description="Show selected reviews again")
    def show(self, request, queryset):
        for review in queryset:
            services.set_hidden(review, False, request.user)
        self.message_user(request, f"{queryset.count()} review(s) shown.", messages.SUCCESS)
