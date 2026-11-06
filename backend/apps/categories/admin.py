from django.contrib import admin
from unfold.admin import ModelAdmin
from common.admin_display import thumbnail

from .models import Category


@admin.register(Category)
class CategoryAdmin(ModelAdmin):
    photo = thumbnail(lambda c: c.icon)
    list_display = [
        "photo","name", "name_hi", "sort_order", "is_active", "requires_compliance"]
    list_editable = ["sort_order", "is_active"]
    prepopulated_fields = {"slug": ["name"]}
    search_fields = ["name", "name_hi"]
