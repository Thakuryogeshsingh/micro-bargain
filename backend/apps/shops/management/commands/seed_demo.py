"""Demo data for showing the app: Bharatpur shops with products and live deals.

    python manage.py seed_demo

Safe to run again and again: shops and products are created once, and any product without a live deal gets
a fresh one, so the demo never runs empty (deals expire within hours by design). Demo merchants use phone
numbers 90000001xx and are marked "(Demo)" so they are easy to find and delete in the admin.
"""
import random
from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.categories.models import Category
from apps.deals import services as deal_services
from apps.deals.models import Deal
from apps.merchants.models import MerchantProfile
from apps.products.models import Product
from apps.shops.models import Shop
from apps.shops.services import make_point
from apps.subscriptions.models import MerchantSubscription, Plan

# (phone, owner, shop, category slug, lat, lng, address, delivers, [(product, unit, normal price, discount %, quantity)])
SHOPS = [
    ("9000000101", "Ramesh Gupta", "Gupta Fruit Bhandar", "fruits", 27.2165, 77.4902, "Mathura Gate Road", True, [
        ("सेब (शिमला)", "kg", 160, 30, 15), ("केला", "dozen", 60, 25, 20), ("अनार", "kg", 180, 35, 8), ("पपीता", "kg", 50, 40, 12),
    ]),
    ("9000000102", "Suresh Sharma", "Sharma Sabzi Wala", "vegetables", 27.2131, 77.4871, "Kumher Gate Sabzi Mandi", False, [
        ("टमाटर (देसी)", "kg", 40, 35, 30), ("आलू", "kg", 30, 20, 50), ("प्याज़", "kg", 45, 25, 40), ("पालक", "piece", 20, 50, 25),
        ("भिंडी", "kg", 60, 40, 10),
    ]),
    ("9000000103", "Mahesh Yadav", "Bharatpur Dairy", "dairy", 27.2098, 77.4935, "Chowburja Road", True, [
        ("दूध (फुल क्रीम)", "litre", 66, 15, 40), ("पनीर", "kg", 380, 25, 6), ("दही", "kg", 80, 30, 15),
    ]),
    ("9000000104", "Vinod Agarwal", "Agarwal Kirana Store", "grocery", 27.2185, 77.4840, "Laxman Mandir Road", True, [
        ("आटा (5 किलो)", "packet", 240, 15, 20), ("बासमती चावल", "kg", 120, 20, 25), ("अरहर दाल", "kg", 160, 18, 20),
        ("सरसों तेल (1 लीटर)", "litre", 180, 12, 15),
    ]),
    ("9000000105", "Pooja Jain", "Fresh Bake House", "bakery", 27.2070, 77.4965, "Krishna Nagar", False, [
        ("ब्रेड", "packet", 45, 40, 20), ("केक (500 ग्राम)", "piece", 350, 45, 5), ("बिस्कुट / कुकीज़", "packet", 120, 35, 15),
    ]),
    ("9000000106", "Rakesh Meena", "Meena Fruits & Juice", "fruits", 27.2045, 77.4990, "Ranjeet Nagar", True, [
        ("मौसमी", "kg", 70, 30, 25), ("अंगूर", "kg", 120, 40, 10), ("तरबूज़", "piece", 80, 35, 8),
    ]),
]

DEAL_HOURS = (6, 8, 12, 18, 24)


class Command(BaseCommand):
    help = "Create demo shops, products and live deals around Bharatpur (idempotent)."

    def handle(self, *args, **options):
        created_deals = 0
        premium = Plan.objects.filter(code="premium").first()
        for phone, owner, shop_name, slug, lat, lng, address, delivers, products in SHOPS:
            with transaction.atomic():
                shop = self._shop(phone, owner, f"{shop_name} (Demo)", slug, lat, lng, address, delivers, premium)
                for name, unit, price, discount, quantity in products:
                    product, _ = Product.objects.get_or_create(
                        shop=shop, name=name,
                        defaults={"category": shop.category, "unit": unit, "standard_price": Decimal(price)},
                    )
                    created_deals += self._ensure_live_deal(shop, product, price, discount, quantity)
        self.stdout.write(self.style.SUCCESS(f"Demo data ready: {len(SHOPS)} shops, {created_deals} new live deal(s)."))

    def _shop(self, phone, owner, name, slug, lat, lng, address, delivers, premium):
        user, _ = User.objects.get_or_create(
            phone=phone, defaults={"name": owner, "role": User.Role.MERCHANT, "is_phone_verified": True}
        )
        category = Category.objects.get(slug=slug)
        merchant, _ = MerchantProfile.objects.get_or_create(
            user=user, defaults={"owner_name": owner, "business_category": category, "status": MerchantProfile.Status.APPROVED},
        )
        shop = merchant.shops.first() or Shop.objects.create(
            merchant=merchant, name=name, category=category, phone=phone, address_line=address, city="Bharatpur",
            state="Rajasthan", pincode="321001", location=make_point(lat, lng), offers_delivery=delivers,
            status=Shop.Status.APPROVED, reviewed_at=timezone.now(),
        )
        # Premium plan so the demo merchants are not held back by the free plan's 3-live-deal limit.
        now = timezone.now()
        if premium and not merchant.subscriptions.filter(status=MerchantSubscription.Status.ACTIVE, ends_at__gt=now).exists():
            MerchantSubscription.objects.create(
                merchant=merchant, plan=premium, amount=0, status=MerchantSubscription.Status.ACTIVE,
                starts_at=now, ends_at=now + timedelta(days=365),
            )
        return shop

    def _ensure_live_deal(self, shop, product, price, discount, quantity):
        soon = timezone.now() + timedelta(hours=1)
        if Deal.objects.filter(product=product, status=Deal.Status.ACTIVE, expires_at__gt=soon).exists():
            return 0
        normal = Decimal(price)
        offer = (normal * (100 - discount) / 100).quantize(Decimal("1"))
        deal_services.create_deal(
            shop.merchant.user, shop=shop, product=product, normal_price=normal, offer_price=offer,
            quantity_total=Decimal(quantity), duration_minutes=random.choice(DEAL_HOURS) * 60,
            description="आज की ताज़ा खेप — जल्दी लें!",
            fulfilment=Deal.Fulfilment.BOTH if shop.offers_delivery else Deal.Fulfilment.PICKUP,
            publish=True,
        )
        return 1
