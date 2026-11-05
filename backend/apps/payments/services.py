"""Business logic for payments (doc section 10.7).

1. App calls create_payment -> we create a Razorpay order and the app opens Razorpay Checkout.
2. App sends the checkout result to verify(); the signature is checked on the server.
3. Razorpay also calls the webhook; whichever of (2)/(3) arrives first marks the payment paid,
   the other is a no-op (row lock + status check), and duplicate webhooks are ignored by event id.
"""
import hashlib
import json
import logging
from decimal import Decimal

from django.db import transaction
from django.db.models import F
from django.utils import timezone

from apps.audit.services import record
from apps.notifications import services as notifications
from common.exceptions import BusinessRuleError

from . import gateway
from .models import Payment, Refund, WebhookEvent

logger = logging.getLogger(__name__)

Purpose = Payment.Purpose


def to_paise(amount):
    return int((amount * 100).to_integral_value())


def _payable(user, purpose, object_id):
    """The thing being paid for, scoped to the user, and its amount."""
    from apps.advertisements.models import Advertisement
    from apps.orders.models import Order
    from apps.subscriptions.models import MerchantSubscription

    if purpose == Purpose.ORDER:
        obj = Order.objects.filter(customer=user, pk=object_id).first()
        if obj is None or obj.status != Order.Status.PENDING_PAYMENT:
            raise BusinessRuleError("This order is not waiting for payment.", "not_payable")
        return {"order": obj}, obj.total_amount, obj.order_number
    if purpose == Purpose.MEMBERSHIP:
        from apps.customers.models import PlusMembership

        obj = PlusMembership.objects.filter(user=user, pk=object_id).first()
        if obj is None or obj.status != PlusMembership.Status.PENDING_PAYMENT:
            raise BusinessRuleError("This membership is not waiting for payment.", "not_payable")
        return {"membership": obj}, obj.amount, f"PLUS-{obj.id}"
    if purpose == Purpose.SUBSCRIPTION:
        obj = MerchantSubscription.objects.filter(merchant__user=user, pk=object_id).first()
        if obj is None or obj.status != MerchantSubscription.Status.PENDING_PAYMENT:
            raise BusinessRuleError("This plan purchase is not waiting for payment.", "not_payable")
        return {"subscription": obj}, obj.amount, f"SUB-{obj.id}"
    obj = Advertisement.objects.filter(shop__merchant__user=user, pk=object_id).first()
    if obj is None or obj.status != Advertisement.Status.PENDING_PAYMENT:
        raise BusinessRuleError("This promotion is not waiting for payment.", "not_payable")
    return {"advertisement": obj}, obj.price, f"AD-{obj.id}"


def create_payment(user, purpose, object_id):
    target, amount, receipt = _payable(user, purpose, object_id)
    try:
        gateway_order = gateway.create_order(to_paise(amount), receipt, {"purpose": purpose, "receipt": receipt})
    except gateway.GatewayError as exc:
        raise BusinessRuleError(f"Payment could not be started: {exc}", "gateway_error")
    return Payment.objects.create(
        user=user, purpose=purpose, amount=amount, gateway_order_id=gateway_order["id"], **target
    )


def verify(user, gateway_order_id, gateway_payment_id, signature):
    payment = Payment.objects.filter(user=user, gateway_order_id=gateway_order_id).first()
    if payment is None:
        raise BusinessRuleError("Payment not found.", "payment_not_found")
    if not gateway.signature_ok(gateway_order_id, gateway_payment_id, signature):
        logger.warning("Bad checkout signature for %s", gateway_order_id)
        raise BusinessRuleError("Payment could not be verified.", "payment_verification_failed")
    return mark_paid(payment.id, gateway_payment_id)


@transaction.atomic
def mark_paid(payment_id, gateway_payment_id, method=""):
    payment = Payment.objects.select_for_update().get(pk=payment_id)
    if payment.status == Payment.Status.PAID:
        return payment  # verify and webhook both arrived; the second one does nothing
    payment.status = Payment.Status.PAID
    payment.gateway_payment_id = gateway_payment_id
    payment.method = method or payment.method
    payment.paid_at = timezone.now()
    payment.error = ""
    payment.save(update_fields=["status", "gateway_payment_id", "method", "paid_at", "error", "updated_at"])
    _fulfil(payment)
    return payment


def _fulfil(payment):
    if payment.purpose == Purpose.ORDER:
        from apps.orders import services as orders

        already_paid = payment.order.payments.filter(status=Payment.Status.PAID).exclude(pk=payment.pk).exists()
        if already_paid or not orders.mark_paid(payment.order):
            reason = "Duplicate payment" if already_paid else "Order was cancelled before the payment arrived"
            _create_refund(payment, payment.amount, reason)
    elif payment.purpose == Purpose.MEMBERSHIP:
        from apps.customers.services import activate_plus

        activate_plus(payment.membership)
    elif payment.purpose == Purpose.SUBSCRIPTION:
        from apps.subscriptions.services import activate

        activate(payment.subscription)
    else:
        from apps.advertisements.services import activate

        activate(payment.advertisement)


# ---------- refunds ----------

def refund_order(order, amount, reason, actor=None):
    """Refund (part of) an order's online payment. Call inside a transaction that holds the order lock."""
    from apps.orders.models import Order

    amount = Decimal(amount)
    if amount <= 0 or order.refunded_amount + amount > order.total_amount:
        raise BusinessRuleError(
            f"Refund must be between ₹0.01 and ₹{order.total_amount - order.refunded_amount}.", "invalid_refund_amount"
        )
    payment = order.payments.filter(status=Payment.Status.PAID).order_by("paid_at").first()
    if payment is None:
        raise BusinessRuleError("This order has no online payment to refund.", "no_payment")
    refund = _create_refund(payment, amount, reason, actor)
    Order.objects.filter(pk=order.pk).update(refunded_amount=F("refunded_amount") + amount)
    order.refresh_from_db(fields=["refunded_amount"])
    order.payment_status = (
        Order.PaymentStatus.REFUNDED if order.refunded_amount >= order.total_amount else Order.PaymentStatus.PARTIALLY_REFUNDED
    )
    order.save(update_fields=["payment_status", "updated_at"])
    notifications.notify(
        order.customer, notifications.Kind.REFUND, f"₹{amount} रिफंड शुरू",
        f"ऑर्डर {order.order_number} का पैसा 5-7 दिन में आपके खाते में आ जाएगा।", data={"order_id": str(order.id)},
    )
    return refund


def refund_payment(payment, amount, reason, actor=None):
    """Refund a non-order payment (e.g. a rejected promotion)."""
    return _create_refund(payment, Decimal(amount), reason, actor)


def _create_refund(payment, amount, reason, actor=None):
    refund = Refund.objects.create(payment=payment, amount=amount, reason=reason[:255], created_by=actor)
    record(actor, "refund.created", refund, reason, amount=amount, payment=payment.gateway_payment_id)
    from .tasks import process_refund

    transaction.on_commit(lambda: process_refund.delay(refund.id), robust=True)
    return refund


def process_refund(refund_id):
    """Ask the gateway to send the money back. Safe to retry: only pending/failed refunds without a gateway id are sent."""
    with transaction.atomic():
        refund = Refund.objects.select_for_update().select_related("payment").get(pk=refund_id)
        if refund.gateway_refund_id or refund.status == Refund.Status.PROCESSED:
            return refund
        try:
            result = gateway.refund(
                refund.payment.gateway_payment_id, to_paise(refund.amount), {"reason": refund.reason[:200]}
            )
        except gateway.GatewayError as exc:
            refund.status = Refund.Status.FAILED
            refund.error = str(exc)[:255]
            refund.save(update_fields=["status", "error", "updated_at"])
            logger.error("Refund %s failed: %s", refund.id, exc)
            return refund
        refund.gateway_refund_id = result["id"]
        refund.status = Refund.Status.PROCESSED if result.get("status") == "processed" else Refund.Status.PENDING
        refund.error = ""
        refund.save(update_fields=["gateway_refund_id", "status", "error", "updated_at"])
        return refund


# ---------- webhook ----------

def handle_webhook(body, signature, event_id):
    if not gateway.webhook_signature_ok(body, signature):
        raise BusinessRuleError("Invalid webhook signature.", "invalid_signature")
    payload = json.loads(body)
    event = payload.get("event", "")
    with transaction.atomic():
        # Razorpay sends X-Razorpay-Event-Id; fall back to a hash of the body.
        _, created = WebhookEvent.objects.get_or_create(
            event_id=event_id or hashlib.sha256(body).hexdigest()[:64], defaults={"event": event, "payload": payload}
        )
        if not created:
            return "duplicate"
        entity = payload.get("payload", {})
        if event in ("payment.captured", "order.paid"):
            p = entity["payment"]["entity"]
            payment = Payment.objects.filter(gateway_order_id=p.get("order_id")).first()
            if payment:
                mark_paid(payment.id, p["id"], p.get("method", ""))
        elif event == "payment.failed":
            p = entity["payment"]["entity"]
            Payment.objects.filter(gateway_order_id=p.get("order_id"), status=Payment.Status.CREATED).update(
                status=Payment.Status.FAILED, error=(p.get("error_description") or "")[:255], updated_at=timezone.now()
            )
        elif event in ("refund.processed", "refund.failed"):
            r = entity["refund"]["entity"]
            status = Refund.Status.PROCESSED if event == "refund.processed" else Refund.Status.FAILED
            Refund.objects.filter(gateway_refund_id=r["id"]).update(status=status, updated_at=timezone.now())
    return event
