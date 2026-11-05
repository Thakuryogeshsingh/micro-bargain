from django.contrib import admin

from .models import Conversation, Message


class MessageInline(admin.TabularInline):
    model = Message
    extra = 0
    readonly_fields = ["sender", "text", "created_at"]


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ["customer", "shop", "last_message_at"]
    search_fields = ["customer__phone", "shop__name"]
    raw_id_fields = ["customer", "shop"]
    inlines = [MessageInline]
