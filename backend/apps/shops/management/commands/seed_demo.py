"""Demo data for showing the app: Bharatpur shops in every category, live deals, customers, purchases and reviews.

    python manage.py seed_demo

Safe to run again and again (the demo server runs it hourly): shops, products and customers are created once,
any product without a live deal gets a fresh one, and a few new purchases with reviews are added whenever recent
activity runs low, so ratings, the mohalla ranking and savings always look alive. Demo merchants use phone
numbers 90000001xx and demo customers 90000002xx, so they are easy to find and delete in the admin.
"""
import random
from datetime import time, timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.categories.models import Category
from apps.deals import services as deal_services
from apps.deals.models import Deal
from apps.merchants.models import MerchantProfile
from apps.orders.models import Coupon
from apps.products.models import Product
from apps.reservations import services as reservations
from apps.reservations.models import DealReservation
from apps.reviews import services as reviews
from apps.shops.models import Shop
from apps.shops.services import make_point
from apps.subscriptions.models import MerchantSubscription, Plan
from common.exceptions import BusinessRuleError

from ...demo_data import COUPONS, CUSTOMERS, REVIEWS, SHOPS

DEAL_HOURS = (2, 4, 6, 8, 12, 18, 24)
DESCRIPTIONS = (
    "आज की ताज़ा खेप — जल्दी लें!", "स्टॉक सीमित है, पहले आओ पहले पाओ।", "शाम तक बिक जाना चाहिए, इसलिए भारी छूट।",
    "क्वालिटी पक्की, दाम आधे।", "",
)
RECENT_PURCHASES_TARGET = 45  # completed pickups by demo customers in the last 3 days


def _time(text):
    hours, minutes = text.split(":")
    return time(int(hours), int(minutes))


class Command(BaseCommand):
    help = "Create demo shops, products, live deals, customers and reviews around Bharatpur (idempotent)."

    def handle(self, *args, **options):
        created_deals = 0
        premium = Plan.objects.filter(code="premium").first()
        for row in SHOPS:
            products = row[-1]
            with transaction.atomic():
                shop = self._shop(*row[:-1], premium=premium)
                for name, unit, price, discount, quantity in products:
                    product, _ = Product.objects.get_or_create(
                        shop=shop, name=name,
                        defaults={"category": shop.category, "unit": unit, "standard_price": Decimal(price)},
                    )
                    created_deals += self._ensure_live_deal(shop, product, price, discount, quantity)
        self._offers()
        purchases = self._activity()
        self.stdout.write(self.style.SUCCESS(
            f"Demo data ready: {len(SHOPS)} shops, {created_deals} new live deal(s), {purchases} new purchase(s)."
        ))

    def _shop(self, phone, owner, name, slug, lat, lng, address, delivers, opens, closes, happy, description, *, premium):
        user, _ = User.objects.get_or_create(
            phone=phone, defaults={"name": owner, "role": User.Role.MERCHANT, "is_phone_verified": True}
        )
        category = Category.objects.get(slug=slug)
        merchant, _ = MerchantProfile.objects.get_or_create(
            user=user, defaults={"owner_name": owner, "business_category": category, "status": MerchantProfile.Status.APPROVED},
        )
        if merchant.onboarding_submitted_at is None:
            merchant.upi_id = f"{phone}@upi"
            merchant.onboarding_submitted_at = timezone.now()
            merchant.save(update_fields=["upi_id", "onboarding_submitted_at", "updated_at"])
        details = {
            "name": name, "description": description, "category": category, "phone": phone, "address_line": address,
            "city": "Bharatpur", "state": "Rajasthan", "pincode": "321001", "offers_delivery": delivers,
            "opening_time": _time(opens), "closing_time": _time(closes), "prep_minutes": random.choice((10, 15, 15, 20, 25)),
            "happy_hour_enabled": happy > 0, "happy_hour_percent": happy or 15,
        }
        shop = merchant.shops.first()
        if shop is None:
            shop = Shop.objects.create(
                merchant=merchant, location=make_point(lat, lng), status=Shop.Status.APPROVED, reviewed_at=timezone.now(), **details
            )
        else:  # older demo shops: refresh their details (and drop the old "(Demo)" suffix)
            details.pop("prep_minutes")
            Shop.objects.filter(pk=shop.pk).update(**details)
            shop.refresh_from_db()
        # Premium plan so the demo merchants are not held back by the free plan's live-deal limit.
        now = timezone.now()
        if premium and not merchant.subscriptions.filter(status=MerchantSubscription.Status.ACTIVE, ends_at__gt=now).exists():
            MerchantSubscription.objects.create(
                merchant=merchant, plan=premium, amount=0, status=MerchantSubscription.Status.ACTIVE,
                starts_at=now, ends_at=now + timedelta(days=365),
            )
        return shop

    def _ensure_live_deal(self, shop, product, price, discount, quantity):
        soon = timezone.now() + timedelta(minutes=30)
        if Deal.objects.filter(product=product, status=Deal.Status.ACTIVE, expires_at__gt=soon).exists():
            return 0
        normal = Decimal(price)
        # A little variety so the same product doesn't always show the same discount.
        discount = max(5, min(60, discount + random.choice((-5, 0, 0, 5))))
        offer = (normal * (100 - discount) / 100).quantize(Decimal("1"))
        try:
            deal_services.create_deal(
                shop.merchant.user, shop=shop, product=product, normal_price=normal, offer_price=offer,
                quantity_total=Decimal(quantity), duration_minutes=random.choice(DEAL_HOURS) * 60,
                description=random.choice(DESCRIPTIONS),
                fulfilment=Deal.Fulfilment.BOTH if shop.offers_delivery else Deal.Fulfilment.PICKUP,
                publish=True,
            )
        except BusinessRuleError as error:
            self.stderr.write(f"{shop.name} / {product.name}: {error}")
            return 0
        return 1

    def _offers(self):
        """Sample coupons; extended so they never run out on the demo server."""
        now = timezone.now()
        for code, text, kind, value, cap, minimum, shop_name, first in COUPONS:
            Coupon.objects.update_or_create(code=code, defaults={
                "description": text, "discount_type": kind, "value": Decimal(value),
                "max_discount": Decimal(cap) if cap else None, "min_order_amount": Decimal(minimum),
                "shop": Shop.objects.filter(name=shop_name).first() if shop_name else None,
                "first_order_only": first, "per_customer_limit": 1 if first else 3,
                "valid_from": now - timedelta(days=1), "valid_until": now + timedelta(days=30), "is_active": True,
            })

    def _activity(self):
        """Completed pickups (with reviews) by demo customers, spread over the last 3 days."""
        customers = [
            User.objects.get_or_create(phone=phone, defaults={"name": name, "role": User.Role.CUSTOMER, "is_phone_verified": True})[0]
            for phone, name in CUSTOMERS
        ]
        now = timezone.now()
        recent = DealReservation.objects.filter(
            customer__phone__startswith="90000002", status="completed", completed_at__gte=now - timedelta(days=3)
        ).count()
        wanted = max(0, RECENT_PURCHASES_TARGET - recent)
        deals = list(deal_services.live_deals().filter(shop__merchant__user__phone__startswith="90000001").select_related("shop"))
        random.shuffle(deals)
        made = 0
        for deal in deals:
            if made >= wanted:
                break
            customer = random.choice(customers)
            quantity = Decimal("1") if deal.unit not in ("kg", "litre") else random.choice((Decimal("1"), Decimal("2")))
            try:
                with transaction.atomic():
                    reservation = reservations.create_reservation(customer, deal.id, quantity)
                    reservations.confirm(reservation)
                    reservation = reservations.complete(reservation, reservation.pickup_code)
                    when = now - timedelta(minutes=random.randint(30, 3 * 24 * 60))
                    DealReservation.objects.filter(pk=reservation.pk).update(
                        created_at=when - timedelta(minutes=20), confirmed_at=when - timedelta(minutes=15), completed_at=when
                    )
                    if random.random() < 0.7:
                        rating, comment = random.choice(REVIEWS)
                        reviews.create_review(customer, rating, comment, reservation=reservation)
                made += 1
            except BusinessRuleError:
                continue  # sold out, or this customer already has it open: try the next deal
        return made
