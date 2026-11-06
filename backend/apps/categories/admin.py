from django.contrib import admin
from unfold.admin import ModelAdmin

from .models import Category


@admin.register(Category)
class CategoryAdmin(ModelAdmin):
    list_display = ["name", "name_hi", "sort_order", "is_active", "requires_compliance"]
    list_editable = ["sort_order", "is_active"]
    prepopulated_fields = {"slug": ["name"]}
    search_fields = ["name", "name_hi"]
