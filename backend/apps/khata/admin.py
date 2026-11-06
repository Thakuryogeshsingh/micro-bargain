from django.contrib import admin
from unfold.admin import ModelAdmin, TabularInline

from .models import KhataCustomer, KhataEntry


class EntryInline(TabularInline):
    model = KhataEntry
    extra = 0
    readonly_fields = ["created_at", "created_by"]


@admin.register(KhataCustomer)
class KhataCustomerAdmin(ModelAdmin):
    list_display = ["name", "phone", "shop", "created_at"]
    search_fields = ["name", "phone", "shop__name"]
    raw_id_fields = ["shop"]
    inlines = [EntryInline]
