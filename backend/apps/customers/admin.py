from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline
from common.admin_display import status_badge as badge

from .models import PlusMembership, Address, CustomerProfile


class AddressInline(TabularInline):
    model = Address
    fk_name = "user"
    extra = 0


@admin.register(CustomerProfile)
class CustomerProfileAdmin(ModelAdmin):
    list_display = ["user", "search_radius_m", "notify_nearby_deals", "created_at"]
    search_fields = ["user__phone", "user__name"]
    raw_id_fields = ["user"]


@admin.register(Address)
class AddressAdmin(ModelAdmin):
    list_display = ["user", "label", "city", "pincode", "is_default"]
    search_fields = ["user__phone", "address_line", "pincode"]
    raw_id_fields = ["user"]


@admin.register(PlusMembership)
class PlusMembershipAdmin(ModelAdmin):
    status_badge = badge("status", "Status")
    list_display = ["user", "status_badge", "amount", "starts_at", "ends_at"]
    list_filter = ["status"]
    search_fields = ["user__phone"]
    raw_id_fields = ["user"]
