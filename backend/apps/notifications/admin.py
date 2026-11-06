from django.contrib.gis import admin
from unfold.admin import ModelAdmin

from .models import Device, Notification


@admin.register(Notification)
class NotificationAdmin(ModelAdmin):
    list_display = ["user", "kind", "title", "push_status", "is_read", "created_at"]
    list_filter = ["kind", "push_status", "is_read"]
    search_fields = ["user__phone", "title", "body"]
    raw_id_fields = ["user", "deal"]
    readonly_fields = ["created_at", "read_at"]
    date_hierarchy = "created_at"


@admin.register(Device)
class DeviceAdmin(admin.GISModelAdmin):
    list_display = ["user", "platform", "is_active", "last_seen_at"]
    list_filter = ["platform", "is_active"]
    search_fields = ["user__phone", "token"]
    raw_id_fields = ["user"]
