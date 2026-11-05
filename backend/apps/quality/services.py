"""Quality assurance: complaints about bad goods, refunds to the wallet, and each shop's quality score.

Flow: customer complains with a photo within QUALITY_COMPLAINT_HOURS of pickup/delivery -> the shop refunds or
disputes within QUALITY_SHOP_REPLY_HOURS (no reply = automatic full refund) -> disputes are decided in the admin.
"""
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from apps.audit.services import record
from apps.customers.models import WalletEntry
from apps.notifications import services as notifications
from apps.shops.models import Shop
from common.exceptions import BusinessRuleError

from .models import QualityComplaint

Status = QualityComplaint.Status


def _paid(source, is_order):
    if is_order:
        return source.total_amount + source.wallet_used - source.refunded_amount
    return source.total_amount


@transaction.atomic
def create_complaint(customer, reason, photo, description="", reservation=None, order=None):
    source = reservation or order
    if (reservation is None) == (order is None):
        raise BusinessRuleError("Complain about either a reservation or an order.", "invalid_source")
    if source.customer_id != customer.id:
        raise BusinessRuleError("You can only complain about your own purchases.", "not_yours")
    if source.status != "completed" or source.completed_at is None:
        raise BusinessRuleError("You can complain only after pickup or delivery.", "not_completed")
    if timezone.now() - source.completed_at > timedelta(hours=settings.QUALITY_COMPLAINT_HOURS):
        raise BusinessRuleError(
            f"Complaints must be made within {settings.QUALITY_COMPLAINT_HOURS} hours of pickup/delivery.", "too_late"
        )
    if QualityComplaint.objects.filter(reservation=reservation, order=order).exists():
        raise BusinessRuleError("A complaint for this purchase already exists.", "duplicate")
    complaint = QualityComplaint.objects.create(
        customer=customer, shop=source.shop, reservation=reservation, order=order, reason=reason,
        description=description, photo=photo, amount_paid=_paid(source, order is not None),
    )
    notifications.notify(
        source.shop.merchant.user, notifications.Kind.QUALITY_COMPLAINT, "⚠️ क्वालिटी की शिकायत",
        f"{complaint.reference}: {complaint.get_reason_display()}. {settings.QUALITY_SHOP_REPLY_HOURS} घंटे में जवाब दें, "
        "वरना ग्राहक को पूरा पैसा अपने आप वापस हो जाएगा।",
        data={"complaint_id": str(complaint.id)},
    )
    return complaint


def _lock(complaint):
    return QualityComplaint.objects.select_for_update().select_related("shop", "customer").get(pk=complaint.pk)


def _refund(complaint, amount, actor, note_field, note):
    amount = Decimal(amount)
    if amount <= 0 or amount > complaint.amount_paid:
        raise BusinessRuleError(f"Refund must be between ₹1 and ₹{complaint.amount_paid}.", "invalid_amount")
    WalletEntry.objects.create(user=complaint.customer, kind=WalletEntry.Kind.REFUND, amount=amount, reference=complaint.reference)
    complaint.status = Status.REFUNDED
    complaint.refund_amount = amount
    setattr(complaint, note_field, note)
    complaint.resolved_at = timezone.now()
    complaint.resolved_by = actor
    complaint.save()
    record(actor, "complaint.refunded", complaint, note, amount=amount)
    notifications.notify(
        complaint.customer, notifications.Kind.REFUND, f"₹{amount} रिफंड वॉलेट में आ गया ✅",
        f"{complaint.shop.name} की शिकायत ({complaint.reference}) का पैसा आपके वॉलेट में है।",
        data={"complaint_id": str(complaint.id)},
    )
    update_quality_score(complaint.shop_id)
    return complaint


@transaction.atomic
def shop_respond(complaint, merchant_user, accept, amount=None, note=""):
    complaint = _lock(complaint)
    if complaint.status != Status.OPEN:
        raise BusinessRuleError("This complaint is already handled.", "invalid_status")
    if accept:
        return _refund(complaint, amount or complaint.amount_paid, merchant_user, "shop_note", note)
    if not note.strip():
        raise BusinessRuleError("Tell the customer why you disagree.", "note_required")
    complaint.status = Status.DISPUTED
    complaint.shop_note = note
    complaint.save(update_fields=["status", "shop_note", "updated_at"])
    record(merchant_user, "complaint.disputed", complaint, note)
    notifications.notify(
        complaint.customer, notifications.Kind.QUALITY_COMPLAINT, "शिकायत की जांच हो रही है",
        f"{complaint.shop.name}: {note[:120]}. हमारी टीम 48 घंटे में फैसला करेगी।",
        data={"complaint_id": str(complaint.id)},
    )
    return complaint


@transaction.atomic
def admin_decide(complaint, admin_user, refund, amount=None, note=""):
    complaint = _lock(complaint)
    if complaint.status not in (Status.OPEN, Status.DISPUTED):
        raise BusinessRuleError("This complaint is already closed.", "invalid_status")
    if refund:
        return _refund(complaint, amount or complaint.amount_paid, admin_user, "admin_note", note)
    complaint.status = Status.REJECTED
    complaint.admin_note = note
    complaint.resolved_at = timezone.now()
    complaint.resolved_by = admin_user
    complaint.save()
    record(admin_user, "complaint.rejected", complaint, note)
    notifications.notify(
        complaint.customer, notifications.Kind.QUALITY_COMPLAINT, "शिकायत बंद",
        f"{complaint.reference}: {note or 'जांच में शिकायत सही नहीं पाई गई।'}", data={"complaint_id": str(complaint.id)},
    )
    update_quality_score(complaint.shop_id)
    return complaint


def auto_refund_unanswered():
    """Shops that don't reply in time: the customer gets a full refund. Run every 30 minutes."""
    due = QualityComplaint.objects.filter(
        status=Status.OPEN, created_at__lte=timezone.now() - timedelta(hours=settings.QUALITY_SHOP_REPLY_HOURS)
    )
    count = 0
    for complaint in due:
        with transaction.atomic():
            complaint = _lock(complaint)
            if complaint.status == Status.OPEN:
                _refund(complaint, complaint.amount_paid, None, "admin_note", "दुकान ने समय पर जवाब नहीं दिया")
                count += 1
    return count


def update_quality_score(shop_id):
    """Share of the last 30 days' purchases without an upheld complaint, 0-100."""
    from apps.orders.models import Order
    from apps.reservations.models import DealReservation

    since = timezone.now() - timedelta(days=30)
    purchases = (
        DealReservation.objects.filter(shop_id=shop_id, status="completed", completed_at__gte=since).count()
        + Order.objects.filter(shop_id=shop_id, status__in=("completed", "refunded"), completed_at__gte=since).count()
    )
    bad = QualityComplaint.objects.filter(shop_id=shop_id, status=Status.REFUNDED, created_at__gte=since).count()
    score = 100 if purchases == 0 else max(0, round(100 * (1 - bad / purchases)))
    Shop.objects.filter(pk=shop_id).update(quality_score=score, quality_purchases_30d=purchases)
    return score


def refresh_all_scores():
    for shop_id in Shop.objects.filter(status=Shop.Status.APPROVED).values_list("id", flat=True):
        update_quality_score(shop_id)
