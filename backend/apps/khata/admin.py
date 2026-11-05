from django.contrib import admin

from .models import KhataCustomer, KhataEntry


class EntryInline(admin.TabularInline):
    model = KhataEntry
    extra = 0
    readonly_fields = ["created_at", "created_by"]


@admin.register(KhataCustomer)
class KhataCustomerAdmin(admin.ModelAdmin):
    list_display = ["name", "phone", "shop", "created_at"]
    search_fields = ["name", "phone", "shop__name"]
    raw_id_fields = ["shop"]
    inlines = [EntryInline]
