"""Business logic for support tickets."""
import secrets

from django.db import transaction
from django.utils import timezone

from apps.notifications import services as notifications
from common.exceptions import BusinessRuleError

from .models import Complaint, ComplaintMessage

Status = Complaint.Status


def _ticket_number():
    while True:
        number = f"T-{secrets.randbelow(10**6):06d}"
        if not Complaint.objects.filter(ticket_number=number).exists():
            return number


def _priority(user):
    """Payment problems, and merchants whose plan includes priority support, go to the top of the queue."""
    if user.is_merchant and hasattr(user, "merchant_profile"):
        from apps.subscriptions.services import current_plan

        if current_plan(user.merchant_profile).priority_support:
            return Complaint.Priority.HIGH
    return Complaint.Priority.NORMAL


@transaction.atomic
def create_complaint(user, category, subject, message, order=None, reservation=None):
    priority = Complaint.Priority.HIGH if category == Complaint.Category.PAYMENT else _priority(user)
    complaint = Complaint.objects.create(
        ticket_number=_ticket_number(), user=user, category=category, subject=subject,
        order=order, reservation=reservation, priority=priority,
    )
    ComplaintMessage.objects.create(complaint=complaint, sender=user, message=message)
    return complaint


def add_user_message(complaint, user, message):
    if complaint.status == Status.CLOSED:
        raise BusinessRuleError("This ticket is closed. Please open a new one.", "ticket_closed")
    ComplaintMessage.objects.create(complaint=complaint, sender=user, message=message)
    if complaint.status == Status.RESOLVED:  # the user is not satisfied: reopen
        complaint.status = Status.OPEN
        complaint.save(update_fields=["status", "updated_at"])
    return complaint


@transaction.atomic
def staff_reply(complaint, staff_user, message, resolve=False):
    ComplaintMessage.objects.create(complaint=complaint, sender=staff_user, message=message, is_staff_reply=True)
    complaint.status = Status.RESOLVED if resolve else Status.IN_PROGRESS
    complaint.resolved_at = timezone.now() if resolve else None
    complaint.assigned_to = complaint.assigned_to or staff_user
    complaint.save(update_fields=["status", "resolved_at", "assigned_to", "updated_at"])
    notifications.notify(
        complaint.user, notifications.Kind.SUPPORT_REPLY, f"सपोर्ट का जवाब ({complaint.ticket_number})", message[:200],
        data={"complaint_id": str(complaint.id)},
    )
    return complaint
