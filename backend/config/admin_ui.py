"""Admin panel look (django-unfold): Fresh colours, grouped sidebar, and the home page numbers."""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Count, Sum
from django.templatetags.static import static
from django.urls import reverse_lazy
from django.utils import timezone


def _link(title, icon, url_name):
    return {"title": title, "icon": icon, "link": reverse_lazy(url_name)}


def _group(title, items):
    return {"title": title, "separator": True, "collapsible": True, "items": items}


UNFOLD = {
    "SITE_TITLE": "Micro Bargain admin",
    "SITE_HEADER": "Micro Bargain",
    "SITE_SUBHEADER": "Bharatpur · admin",
    "SITE_SYMBOL": "sell",
    "SITE_URL": "/legal/terms/",
    "SITE_FAVICONS": [{"rel": "icon", "sizes": "32x32", "type": "image/png", "href": lambda request: static("admin_ui/favicon.png")}],
    "SHOW_HISTORY": True,
    "SHOW_VIEW_ON_SITE": False,
    "SHOW_BACK_BUTTON": True,
    "DASHBOARD_CALLBACK": "config.admin_ui.dashboard",
    "STYLES": [lambda request: static("admin_ui/fresh.css")],
    # Fresh: neutral greys, and the brand green (deep enough to read on white, bright in dark mode).
    "COLORS": {
        "base": {
            "50": "oklch(98.5% 0 0)", "100": "oklch(96.7% 0 0)", "200": "oklch(92.2% 0 0)", "300": "oklch(87% 0 0)",
            "400": "oklch(70.8% 0 0)", "500": "oklch(55.6% 0 0)", "600": "oklch(43.9% 0 0)", "700": "oklch(37.1% 0 0)",
            "800": "oklch(26.9% 0 0)", "900": "oklch(20.5% 0 0)", "950": "oklch(14.5% 0 0)",
        },
        "primary": {
            "50": "oklch(98.2% .018 155.826)", "100": "oklch(96.2% .044 156.743)", "200": "oklch(92.5% .084 155.995)",
            "300": "oklch(87.1% .15 154.449)", "400": "oklch(79.2% .209 151.711)", "500": "oklch(72.3% .219 149.579)",
            "600": "oklch(62.7% .194 149.214)", "700": "oklch(52.7% .154 150.069)", "800": "oklch(44.8% .119 151.328)",
            "900": "oklch(39.3% .095 152.535)", "950": "oklch(26.6% .065 152.934)",
        },
    },
    "SIDEBAR": {
        "show_search": True,
        "show_all_applications": True,
        "navigation": [
            {"title": "Business", "separator": False, "items": [
                {"title": "Home", "icon": "space_dashboard", "link": reverse_lazy("admin:index")},
                {"title": "Reports & Excel", "icon": "monitoring", "link": reverse_lazy("admin-dashboard")},
            ]},
            _group("Shops", [
                _link("Shops", "storefront", "admin:shops_shop_changelist"),
                _link("Shop owners", "badge", "admin:merchants_merchantprofile_changelist"),
                _link("Products", "inventory_2", "admin:products_product_changelist"),
                _link("Deals", "local_offer", "admin:deals_deal_changelist"),
                _link("Categories", "category", "admin:categories_category_changelist"),
                _link("Stock", "warehouse", "admin:inventory_inventory_changelist"),
            ]),
            _group("Customers", [
                _link("Users", "group", "admin:accounts_user_changelist"),
                _link("Customer profiles", "person", "admin:customers_customerprofile_changelist"),
                _link("Addresses", "home_pin", "admin:customers_address_changelist"),
                _link("Bargain Plus", "workspace_premium", "admin:customers_plusmembership_changelist"),
                _link("Favourite shops", "favorite", "admin:shops_favoriteshop_changelist"),
                _link("Reviews", "star", "admin:reviews_review_changelist"),
            ]),
            _group("Orders", [
                _link("Orders", "shopping_bag", "admin:orders_order_changelist"),
                _link("Reservations", "bookmark_added", "admin:reservations_dealreservation_changelist"),
                _link("Daily subscriptions", "event_repeat", "admin:daily_dailyorder_changelist"),
                _link("Daily deliveries", "local_shipping", "admin:daily_dailydelivery_changelist"),
                _link("Coupons", "confirmation_number", "admin:orders_coupon_changelist"),
            ]),
            _group("Money", [
                _link("Payments", "payments", "admin:payments_payment_changelist"),
                _link("Refunds", "currency_exchange", "admin:payments_refund_changelist"),
                _link("Commissions", "percent", "admin:commissions_commission_changelist"),
                _link("Commission rules", "rule", "admin:commissions_commissionrule_changelist"),
                _link("Shop plans", "card_membership", "admin:subscriptions_plan_changelist"),
                _link("Plan purchases", "receipt_long", "admin:subscriptions_merchantsubscription_changelist"),
                _link("Udhaar khata", "menu_book", "admin:khata_khatacustomer_changelist"),
            ]),
            _group("Quality & support", [
                _link("Quality complaints", "report", "admin:quality_qualitycomplaint_changelist"),
                _link("Support tickets", "support_agent", "admin:support_complaint_changelist"),
                _link("Chats", "forum", "admin:chat_conversation_changelist"),
            ]),
            _group("Marketing", [
                _link("Promotions", "campaign", "admin:advertisements_advertisement_changelist"),
                _link("Notifications", "notifications", "admin:notifications_notification_changelist"),
                _link("Devices", "smartphone", "admin:notifications_device_changelist"),
            ]),
            _group("App & system", [
                _link("App releases", "system_update", "admin:releases_apprelease_changelist"),
                _link("Audit log", "history", "admin:audit_auditlog_changelist"),
                _link("Payment webhooks", "webhook", "admin:payments_webhookevent_changelist"),
                _link("OTP log", "password", "admin:accounts_phoneotp_changelist"),
            ]),
        ],
    },
}


def dashboard(request, context):
    """Numbers for the admin home page."""
    from apps.accounts.models import User
    from apps.deals.services import live_deals
    from apps.merchants.models import MerchantProfile
    from apps.orders.models import Order
    from apps.quality.models import QualityComplaint
    from apps.reservations.models import DealReservation
    from apps.shops.models import Shop
    from apps.support.models import Complaint

    now = timezone.now()
    today = timezone.localtime(now).replace(hour=0, minute=0, second=0, microsecond=0)
    week = now - timedelta(days=7)
    orders_today = Order.objects.filter(created_at__gte=today)
    pickups_today = DealReservation.objects.filter(status="completed", completed_at__gte=today)
    sales_today = (orders_today.exclude(status__in=["cancelled", "pending_payment"]).aggregate(s=Sum("total_amount"))["s"] or Decimal(0)) + (
        pickups_today.aggregate(s=Sum("total_amount"))["s"] or Decimal(0))
    pending_shops = Shop.objects.filter(status="pending")
    submitted = MerchantProfile.objects.filter(status="pending", onboarding_submitted_at__isnull=False).count()
    open_quality = QualityComplaint.objects.filter(status__in=["open", "disputed"]).count()
    open_support = Complaint.objects.filter(status__in=[Complaint.Status.OPEN, Complaint.Status.IN_PROGRESS]).count()

    context.update({
        "kpis": [
            {"label": "Sales today", "value": f"₹{sales_today:,.0f}", "icon": "currency_rupee"},
            {"label": "Orders today", "value": orders_today.count(), "icon": "shopping_bag"},
            {"label": "Pickups today", "value": pickups_today.count(), "icon": "bookmark_added"},
            {"label": "Live deals", "value": live_deals().count(), "icon": "local_offer"},
            {"label": "Active shops", "value": Shop.objects.filter(status="approved").count(), "icon": "storefront"},
            {"label": "New customers (7 days)", "value": User.objects.filter(role="customer", date_joined__gte=week).count(),
             "icon": "person_add"},
        ],
        "attention": [
            {"label": "Shops waiting for approval", "count": pending_shops.count(), "icon": "storefront",
             "link": f"{reverse_lazy('admin:shops_shop_changelist')}?status__exact=pending"},
            {"label": "Owners who submitted setup", "count": submitted, "icon": "badge",
             "link": f"{reverse_lazy('admin:merchants_merchantprofile_changelist')}?status__exact=pending"},
            {"label": "Quality complaints to decide", "count": open_quality, "icon": "report",
             "link": f"{reverse_lazy('admin:quality_qualitycomplaint_changelist')}?status__exact=disputed"},
            {"label": "Open support tickets", "count": open_support, "icon": "support_agent",
             "link": reverse_lazy("admin:support_complaint_changelist")},
        ],
        "recent_orders": Order.objects.select_related("shop", "customer").order_by("-created_at")[:8],
        "top_shops": Shop.objects.filter(status="approved").annotate(n=Count("orders")).order_by("-rating_avg", "-n")[:6],
    })
    return context
