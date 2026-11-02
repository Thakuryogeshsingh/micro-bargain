"""Business logic for reservations.

Flow: customer reserves (stock held) -> shop confirms or rejects -> customer picks up with
the pickup code (stock sold), or cancels / the hold expires (stock released).
"""
import secrets
import string
from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.commissions import services as commissions
from apps.deals import services as deal_services
from apps.inventory import services as inventory
from apps.notifications import services as notifications
from common.exceptions import BusinessRuleError

from .models import DealReservation

Status = DealReservation.Status
Kind = notifications.Kind
_ALPHABET = string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789"


def _new_reservation_number():
    while True:
        number = "MB-" + "".join(secrets.choice(_ALPHABET) for _ in range(6))
        if not DealReservation.objects.filter(reservation_number=number).exists():
            return number


def _lock(reservation):
    return DealReservation.objects.select_for_update().get(pk=reservation.pk)


def create_reservation(customer, deal_id, quantity):
    open_count = customer.reservations.filter(status__in=DealReservation.OPEN_STATUSES).count()
    if open_count >= settings.MAX_ACTIVE_RESERVATIONS_PER_CUSTOMER:
        raise BusinessRuleError(
            f"You can have at most {settings.MAX_ACTIVE_RESERVATIONS_PER_CUSTOMER} open reservations.", "reservation_limit"
        )
    try:
        with transaction.atomic():
            if customer.reservations.filter(deal_id=deal_id, status__in=DealReservation.OPEN_STATUSES).exists():
                raise BusinessRuleError("You already have an open reservation for this deal.", "already_reserved")
            deal = deal_services.reserve_quantity(deal_id, quantity)  # locks the deal row
            reservation = DealReservation.objects.create(
                reservation_number=_new_reservation_number(),
                customer=customer,
                deal=deal,
                shop=deal.shop,
                quantity=quantity,
                unit=deal.unit,
                unit_price=deal.offer_price,
                normal_unit_price=deal.normal_price,
                total_amount=deal.offer_price * quantity,
                pickup_code=f"{secrets.randbelow(10000):04d}",
                expires_at=timezone.now() + timedelta(minutes=settings.RESERVATION_HOLD_MINUTES),
            )
            notifications.reservation_event(reservation, Kind.NEW_RESERVATION)
            return reservation
    except IntegrityError:
        # Two simultaneous taps: the unique constraint let only one through.
        raise BusinessRuleError("You already have an open reservation for this deal.", "already_reserved")


def _close(reservation, new_status, reason=""):
    """Close an open reservation and give its stock back to the deal."""
    deal_services.release_quantity(reservation.deal_id, reservation.quantity)
    reservation.status = new_status
    reservation.closed_reason = reason
    reservation.save(update_fields=["status", "closed_reason", "updated_at"])
    return reservation


@transaction.atomic
def confirm(reservation):
    reservation = _lock(reservation)
    if reservation.status != Status.PENDING:
        raise BusinessRuleError(f"Only pending reservations can be confirmed (this one is {reservation.status}).", "invalid_status")
    if reservation.expires_at <= timezone.now():
        raise BusinessRuleError("This reservation has expired.", "reservation_expired")
    reservation.status = Status.CONFIRMED
    reservation.confirmed_at = timezone.now()
    reservation.save(update_fields=["status", "confirmed_at", "updated_at"])
    notifications.reservation_event(reservation, Kind.RESERVATION_CONFIRMED)
    return reservation


@transaction.atomic
def reject(reservation, reason=""):
    reservation = _lock(reservation)
    if reservation.status != Status.PENDING:
        raise BusinessRuleError(f"Only pending reservations can be rejected (this one is {reservation.status}).", "invalid_status")
    _close(reservation, Status.REJECTED, reason or "Rejected by shop.")
    notifications.reservation_event(reservation, Kind.RESERVATION_REJECTED)
    return reservation


@transaction.atomic
def cancel(reservation, reason=""):
    reservation = _lock(reservation)
    if reservation.status not in DealReservation.OPEN_STATUSES:
        raise BusinessRuleError(f"This reservation is already {reservation.status}.", "invalid_status")
    _close(reservation, Status.CANCELLED, reason or "Cancelled by customer.")
    notifications.reservation_event(reservation, Kind.RESERVATION_CANCELLED)
    return reservation


@transaction.atomic
def complete(reservation, pickup_code):
    reservation = _lock(reservation)
    if reservation.status != Status.CONFIRMED:
        raise BusinessRuleError("Confirm the reservation before completing pickup.", "invalid_status")
    if reservation.pickup_code != pickup_code:
        raise BusinessRuleError("Pickup code does not match.", "wrong_pickup_code")
    deal = deal_services.complete_quantity(reservation.deal_id, reservation.quantity)
    inventory.record_sale(deal.product_id, reservation.quantity, reservation.reservation_number)
    commissions.record_for_reservation(reservation)
    reservation.status = Status.COMPLETED
    reservation.completed_at = timezone.now()
    reservation.save(update_fields=["status", "completed_at", "updated_at"])
    notifications.reservation_event(reservation, Kind.RESERVATION_COMPLETED)
    return reservation


def expire_reservations():
    """Release stock held by reservations that were not picked up in time. Run every minute."""
    count = 0
    due = DealReservation.objects.filter(status__in=DealReservation.OPEN_STATUSES, expires_at__lte=timezone.now())
    for reservation_id in due.values_list("id", flat=True):
        with transaction.atomic():
            reservation = DealReservation.objects.select_for_update().get(pk=reservation_id)
            # Re-check under the lock: it may have been completed or cancelled meanwhile.
            if reservation.status in DealReservation.OPEN_STATUSES and reservation.expires_at <= timezone.now():
                _close(reservation, Status.EXPIRED, "Not picked up in time.")
                notifications.reservation_event(reservation, Kind.RESERVATION_EXPIRED)
                count += 1
    return count
