from django.contrib import admin

from .models import PlusMembership, Address, CustomerProfile


class AddressInline(admin.TabularInline):
    model = Address
    fk_name = "user"
    extra = 0


@admin.register(CustomerProfile)
class CustomerProfileAdmin(admin.ModelAdmin):
    list_display = ["user", "search_radius_m", "notify_nearby_deals", "created_at"]
    search_fields = ["user__phone", "user__name"]
    raw_id_fields = ["user"]


@admin.register(Address)
class AddressAdmin(admin.ModelAdmin):
    list_display = ["user", "label", "city", "pincode", "is_default"]
    search_fields = ["user__phone", "address_line", "pincode"]
    raw_id_fields = ["user"]


@admin.register(PlusMembership)
class PlusMembershipAdmin(admin.ModelAdmin):
    list_display = ["user", "status", "amount", "starts_at", "ends_at"]
    list_filter = ["status"]
    search_fields = ["user__phone"]
    raw_id_fields = ["user"]
