from django.contrib import admin

from .models import AppRelease


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    list_display = ["version_name", "version_code", "platform", "force_update", "is_active", "created_at"]
    list_filter = ["platform", "is_active", "force_update"]
