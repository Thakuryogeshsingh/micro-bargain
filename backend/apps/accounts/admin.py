from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import PhoneOTP, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ["-date_joined"]
    list_display = ["phone", "name", "role", "is_phone_verified", "is_active", "date_joined"]
    list_filter = ["role", "is_active", "is_phone_verified", "is_staff"]
    search_fields = ["phone", "name", "email"]
    fieldsets = (
        (None, {"fields": ("phone", "password")}),
        ("Profile", {"fields": ("name", "email", "role", "is_phone_verified")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("phone", "role", "password1", "password2")}),
    )


@admin.register(PhoneOTP)
class PhoneOTPAdmin(admin.ModelAdmin):
    list_display = ["phone", "created_at", "expires_at", "attempts", "is_used"]
    search_fields = ["phone"]
    readonly_fields = ["phone", "code_hash", "created_at", "expires_at", "attempts", "is_used"]

    def has_add_permission(self, request):
        return False
