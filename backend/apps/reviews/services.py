"""Business logic for reviews. Only customers who completed a purchase can review, once per purchase."""
from decimal import ROUND_HALF_UP, Decimal

from django.db import IntegrityError, transaction
from django.db.models import Avg, Count
from django.utils import timezone

from apps.audit.services import record
from apps.notifications import services as notifications
from apps.shops.models import Shop
from common.exceptions import BusinessRuleError

from .models import Review


def _refresh_shop_rating(shop_id):
    shop = Shop.objects.select_for_update().get(pk=shop_id)
    stats = Review.objects.filter(shop_id=shop_id, is_hidden=False).aggregate(avg=Avg("rating"), count=Count("id"))
    shop.rating_avg = Decimal(stats["avg"] or 0).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    shop.rating_count = stats["count"]
    shop.save(update_fields=["rating_avg", "rating_count", "updated_at"])


def create_review(customer, rating, comment="", reservation=None, order=None):
    source = reservation or order
    if (reservation is None) == (order is None):
        raise BusinessRuleError("Review either a reservation or an order.", "invalid_source")
    if source.customer_id != customer.id:
        raise BusinessRuleError("You can only review your own purchases.", "not_yours")
    if source.status != "completed":
        raise BusinessRuleError("You can review only after pickup or delivery is complete.", "not_completed")
    try:
        with transaction.atomic():
            review = Review.objects.create(
                customer=customer, shop=source.shop, reservation=reservation, order=order, rating=rating, comment=comment
            )
            _refresh_shop_rating(source.shop_id)
            notifications.notify(
                source.shop.merchant.user, notifications.Kind.NEW_REVIEW, f"नया रिव्यू: {'★' * rating}",
                comment[:120] or "ग्राहक ने आपकी दुकान को रेटिंग दी।", data={"review_id": str(review.id)},
            )
    except IntegrityError:
        raise BusinessRuleError("You have already reviewed this purchase.", "already_reviewed")
    return review


def reply(review, text):
    review.merchant_reply = text
    review.replied_at = timezone.now()
    review.save(update_fields=["merchant_reply", "replied_at", "updated_at"])
    return review


@transaction.atomic
def set_hidden(review, hidden, actor):
    review.is_hidden = hidden
    review.save(update_fields=["is_hidden", "updated_at"])
    _refresh_shop_rating(review.shop_id)
    record(actor, "review.hidden" if hidden else "review.shown", review)
    return review
