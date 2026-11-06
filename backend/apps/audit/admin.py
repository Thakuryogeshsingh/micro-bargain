from django.contrib import admin
from unfold.admin import ModelAdmin

from .models import AuditLog


@admin.register(AuditLog)
class AuditLogAdmin(ModelAdmin):
    list_display = ["created_at", "actor", "action", "object_type", "object_id", "description"]
    list_filter = ["action", "object_type"]
    search_fields = ["actor__phone", "object_id", "description"]
    date_hierarchy = "created_at"

    # Read-only: an audit trail that can be edited is not an audit trail.
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
