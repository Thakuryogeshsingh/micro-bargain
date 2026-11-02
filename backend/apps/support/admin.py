from django import forms
from django.contrib import admin, messages

from . import services
from .models import Complaint, ComplaintMessage


class MessageInline(admin.TabularInline):
    model = ComplaintMessage
    extra = 0
    can_delete = False
    readonly_fields = ["sender", "is_staff_reply", "message", "created_at"]

    def has_add_permission(self, request, obj=None):
        return False


class ReplyForm(forms.ModelForm):
    reply = forms.CharField(widget=forms.Textarea(attrs={"rows": 3}), required=False, help_text="Sent to the user as a notification")
    mark_resolved = forms.BooleanField(required=False)

    class Meta:
        model = Complaint
        fields = ["status", "priority", "assigned_to"]


@admin.register(Complaint)
class ComplaintAdmin(admin.ModelAdmin):
    form = ReplyForm
    list_display = ["ticket_number", "user", "category", "subject", "priority", "status", "assigned_to", "created_at"]
    list_filter = ["status", "priority", "category"]
    search_fields = ["ticket_number", "user__phone", "subject"]
    raw_id_fields = ["order", "reservation"]
    readonly_fields = ["ticket_number", "user", "category", "subject", "order", "reservation", "resolved_at"]
    fields = ["ticket_number", "user", "category", "subject", "order", "reservation", "status", "priority",
              "assigned_to", "resolved_at", "reply", "mark_resolved"]
    inlines = [MessageInline]

    def has_add_permission(self, request):
        return False

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        reply = form.cleaned_data.get("reply")
        if reply:
            services.staff_reply(obj, request.user, reply, resolve=form.cleaned_data.get("mark_resolved", False))
            self.message_user(request, "Reply sent to the user.", messages.SUCCESS)
