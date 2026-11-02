from django.contrib import admin

from .models import Address, CustomerProfile


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
