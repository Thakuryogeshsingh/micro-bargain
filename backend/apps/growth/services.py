"""Price alerts, mohalla group deals, loyalty points, broadcasts and festival campaigns."""
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.contrib.gis.measure import D
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from apps.accounts.models import User
from apps.notifications import services as notifications
from apps.shops.services import make_point
from common.exceptions import BusinessRuleError

from .models import Broadcast, Campaign, GroupDeal, GroupMember, LoyaltyAccount, LoyaltyEntry, PriceAlert

ALERT_RADIUS_M = 10_000


# ---------- price alerts ----------

def check_price_alerts():
    """Tell people when a live deal nearby matches what they are waiting for (once per deal). Run every 10 minutes."""
    from apps.deals.search import search_terms
    from apps.deals.services import live_deals

    sent = 0
    for alert in PriceAlert.objects.filter(is_active=True).select_related("user"):
        match = Q()
        for term in search_terms(alert.query):
            match |= Q(product__name__icontains=term)
        deals = (live_deals().filter(match, offer_price__lte=alert.max_price,
                                     shop__location__dwithin=(make_point(alert.latitude, alert.longitude), D(m=ALERT_RADIUS_M)))
                 .exclude(id__in=alert.notified_deals.values("id")).select_related("shop", "product").order_by("offer_price"))
        best = deals.first()
        if best is None:
            continue
        notifications.notify(
            alert.user, notifications.Kind.PRICE_ALERT, f"🔔 {best.product.name} अब ₹{best.offer_price:g}",
            f"{best.shop.name} पर — आपकी सीमा ₹{alert.max_price:g} से कम। जल्दी लें!",
            data={"deal_id": str(best.id)}, deal=best,
        )
        alert.notified_deals.add(*deals[:20])
        alert.last_notified_at = timezone.now()
        alert.save(update_fields=["last_notified_at", "updated_at"])
        sent += 1
    return sent


# ---------- shopping list ----------

def shopping_list(items, latitude, longitude, radius=10_000):
    """For each wanted item: the cheapest live deal nearby. Plus the one shop that covers the most items (one order = one shop)."""
    from apps.deals.search import search_terms
    from apps.deals.services import nearby_deals

    rows, by_shop = [], {}
    for raw in items[:20]:
        item = raw.strip()
        if not item:
            continue
        match = Q()
        for term in search_terms(item):
            match |= Q(product__name__icontains=term)
        deals = list(nearby_deals(latitude, longitude, radius).filter(match).order_by("offer_price")[:10])
        rows.append({"item": item, "deals": deals})
        for deal in deals:
            entry = by_shop.setdefault(deal.shop_id, {"shop": deal.shop, "deals": {}})
            entry["deals"].setdefault(item, deal)  # cheapest at that shop for this item
    best = max(by_shop.values(), key=lambda e: (len(e["deals"]), -sum(d.offer_price for d in e["deals"].values())), default=None)
    return rows, best


# ---------- group deals ----------

@transaction.atomic
def start_group(merchant_user, deal, target, extra_percent):
    if deal.shop.merchant.user_id != merchant_user.id:
        raise BusinessRuleError("This is not your deal.", "not_yours")
    group, _ = GroupDeal.objects.update_or_create(deal=deal, defaults={"target": target, "extra_percent": extra_percent})
    return group


@transaction.atomic
def join_group(user, group):
    group = GroupDeal.objects.select_for_update().select_related("deal", "deal__shop", "deal__product").get(pk=group.pk)
    if not group.deal.is_live:
        raise BusinessRuleError("This deal has ended.", "deal_ended")
    GroupMember.objects.get_or_create(group=group, user=user)
    if not group.is_unlocked and group.members.count() >= group.target:
        group.unlocked_at = timezone.now()
        group.save(update_fields=["unlocked_at", "updated_at"])
        for member in group.members.select_related("user"):
            notifications.notify(
                member.user, notifications.Kind.GROUP_DEAL, "🎉 मोहल्ला डील खुल गई!",
                f"{group.deal.product.name} ({group.deal.shop.name}) खरीदें — {group.extra_percent}% और वापस वॉलेट में।",
                data={"deal_id": str(group.deal_id)},
            )
    return group


def reward_group_purchase(customer, deal_id, amount, reference):
    """After a completed purchase: members of an unlocked group get the extra percent in their wallet (once)."""
    from apps.customers.models import WalletEntry

    member = (GroupMember.objects.select_for_update().select_related("group")
              .filter(user=customer, group__deal_id=deal_id, group__unlocked_at__isnull=False, rewarded_at__isnull=True).first())
    if member is None:
        return None
    bonus = (Decimal(amount) * member.group.extra_percent / 100).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if bonus <= 0:
        return None
    WalletEntry.objects.create(user=customer, kind=WalletEntry.Kind.GROUP_BONUS, amount=bonus, reference=reference)
    member.rewarded_at = timezone.now()
    member.save(update_fields=["rewarded_at", "updated_at"])
    notifications.notify(customer, notifications.Kind.CASHBACK, f"🎉 मोहल्ला बोनस ₹{bonus}", "आपके वॉलेट में आ गया।")
    return bonus


# ---------- loyalty ----------

POINTS_PER_RUPEES = 10  # 1 point per ₹10
STREAK_DAYS = 7
STREAK_BONUS = 50
REDEEM_UNIT = 100  # 100 points = ₹10


def award_purchase(customer, amount, reference):
    """Points for a completed purchase, and the daily streak (7 days in a row = bonus)."""
    account, _ = LoyaltyAccount.objects.select_for_update().get_or_create(user=customer)
    points = int(Decimal(amount) // POINTS_PER_RUPEES)
    today = timezone.localdate()
    if account.last_purchase_date != today:
        yesterday = today - timedelta(days=1)
        account.streak_days = account.streak_days + 1 if account.last_purchase_date == yesterday else 1
        account.last_purchase_date = today
        account.best_streak = max(account.best_streak, account.streak_days)
        if account.streak_days % STREAK_DAYS == 0:
            account.points += STREAK_BONUS
            LoyaltyEntry.objects.create(user=customer, kind=LoyaltyEntry.Kind.STREAK, points=STREAK_BONUS, reference=reference)
            notifications.notify(customer, notifications.Kind.CASHBACK, f"🔥 {account.streak_days} दिन की स्ट्रीक!",
                                 f"+{STREAK_BONUS} पॉइंट बोनस मिले।")
    if points:
        account.points += points
        LoyaltyEntry.objects.create(user=customer, kind=LoyaltyEntry.Kind.PURCHASE, points=points, reference=reference)
    account.save()
    return account


@transaction.atomic
def redeem(customer, points):
    from apps.customers.models import WalletEntry

    account, _ = LoyaltyAccount.objects.select_for_update().get_or_create(user=customer)
    if points <= 0 or points % REDEEM_UNIT:
        raise BusinessRuleError(f"Redeem in steps of {REDEEM_UNIT} points.", "invalid_points")
    if points > account.points:
        raise BusinessRuleError("Not enough points.", "not_enough_points")
    rupees = Decimal(points // REDEEM_UNIT * 10)
    account.points -= points
    account.save(update_fields=["points", "updated_at"])
    LoyaltyEntry.objects.create(user=customer, kind=LoyaltyEntry.Kind.REDEEM, points=-points)
    WalletEntry.objects.create(user=customer, kind=WalletEntry.Kind.POINTS, amount=rupees, reference=f"{points} pts")
    return account, rupees


def on_purchase_completed(customer, amount, reference, lines):
    """Called inside the completing transaction of a reservation / order. lines: [(deal_id, line_amount)]."""
    award_purchase(customer, amount, reference)
    for deal_id, line_amount in lines:
        reward_group_purchase(customer, deal_id, line_amount, reference)


# ---------- broadcasts and campaigns ----------

def broadcast_recipients(broadcast):
    users = User.objects.filter(is_active=True)
    if broadcast.audience == Broadcast.Audience.CUSTOMERS:
        users = users.filter(role=User.Role.CUSTOMER)
    elif broadcast.audience == Broadcast.Audience.MERCHANTS:
        users = users.filter(role=User.Role.MERCHANT)
    if broadcast.city:
        users = users.filter(Q(addresses__city__iexact=broadcast.city) | Q(merchant_profile__shops__city__iexact=broadcast.city))
    return users.distinct()


def send_broadcast(broadcast):
    if broadcast.sent_at:
        raise BusinessRuleError("Already sent.", "already_sent")
    count = 0
    for user in broadcast_recipients(broadcast).iterator():
        notifications.notify(user, notifications.Kind.ANNOUNCEMENT, broadcast.title, broadcast.body)
        count += 1
    broadcast.sent_at = timezone.now()
    broadcast.sent_count = count
    broadcast.save(update_fields=["sent_at", "sent_count", "updated_at"])
    return count


def run_campaigns():
    """Every few minutes: switch campaign coupons on/off, announce new campaigns, send scheduled broadcasts."""
    now = timezone.now()
    for campaign in Campaign.objects.filter(coupon__isnull=False).select_related("coupon"):
        live = campaign.starts_at <= now < campaign.ends_at
        coupon = campaign.coupon
        if live and (not coupon.is_active or coupon.valid_from > now or coupon.valid_until < campaign.ends_at):
            coupon.is_active = True
            coupon.valid_from = min(coupon.valid_from, campaign.starts_at)
            coupon.valid_until = campaign.ends_at
            coupon.save(update_fields=["is_active", "valid_from", "valid_until"])
        elif not live and now >= campaign.ends_at and coupon.is_active:
            coupon.is_active = False
            coupon.save(update_fields=["is_active"])
    for campaign in Campaign.objects.filter(announce=True, announced_at__isnull=True, starts_at__lte=now, ends_at__gt=now):
        send_broadcast(Broadcast.objects.create(title=campaign.title, body=campaign.subtitle or campaign.name))
        campaign.announced_at = now
        campaign.save(update_fields=["announced_at", "updated_at"])
    for broadcast in Broadcast.objects.filter(sent_at__isnull=True, send_at__isnull=False, send_at__lte=now):
        send_broadcast(broadcast)


def active_campaigns():
    now = timezone.now()
    return Campaign.objects.filter(starts_at__lte=now, ends_at__gt=now).select_related("coupon")

