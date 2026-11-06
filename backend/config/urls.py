from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import Http404, JsonResponse
from django.shortcuts import render
from django.urls import include, path, re_path
from django.views.static import serve
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from apps.analytics.views import admin_dashboard, admin_report_download

admin.site.site_header = "Micro Bargain admin"
admin.site.site_title = "Micro Bargain"
admin.site.index_title = "Platform management"


def health_check(request):
    return JsonResponse({"status": "ok"})


LEGAL_PAGES = {
    "privacy": "Privacy Policy", "terms": "Terms of Use", "refunds": "Cancellation & Refund Policy", "photo-credits": "Photo credits",
}


def _photo_credits():
    """Authors and licences of the demo photos (CC BY / BY-SA require this attribution)."""
    import json

    manifest = settings.BASE_DIR / "apps" / "shops" / "demo_images" / "manifest.json"
    return json.loads(manifest.read_text(encoding="utf-8")).get("credits", []) if manifest.exists() else []


def deal_share_page(request, pk):
    """Public page for a shared deal link; the app opens it directly when installed."""
    from django.shortcuts import get_object_or_404

    from apps.deals.models import Deal

    deal = get_object_or_404(Deal.objects.select_related("product", "shop").exclude(status="draft"), pk=pk)
    return render(request, "share/deal.html", {"deal": deal, "discount": round(deal.discount_percent), "live": deal.is_live})


def shop_share_page(request, pk):
    """Public page a shop's QR code opens: today's deals, and a button that opens the app."""
    from django.shortcuts import get_object_or_404

    from apps.deals.services import live_deals
    from apps.shops.models import Shop

    shop = get_object_or_404(Shop, pk=pk, status=Shop.Status.APPROVED)
    deals = live_deals().filter(shop=shop).select_related("product").order_by("-discount_percent")[:30]
    return render(request, "share/shop.html", {"shop": shop, "deals": deals})


def bill_page(request, token):
    """Printable bill / GST invoice for an order or a pickup, opened from a link the shop or customer shares."""
    from django.core import signing
    from django.shortcuts import get_object_or_404

    from apps.orders.models import Order
    from apps.reservations.models import DealReservation

    try:
        kind, pk = signing.loads(token, salt="bill").split(":")
    except (signing.BadSignature, ValueError):
        raise Http404
    if kind == "o":
        order = get_object_or_404(Order.objects.select_related("shop", "customer").prefetch_related("items"), pk=pk)
        lines = [{"name": i.product_name, "qty": i.quantity, "unit": i.unit, "mrp": i.normal_unit_price, "price": i.unit_price,
                  "amount": i.line_total} for i in order.items.all()]
        doc = {"number": order.order_number, "date": order.completed_at or order.created_at, "shop": order.shop,
               "customer": order.customer, "lines": lines, "subtotal": order.subtotal, "savings": order.savings,
               "discounts": order.coupon_discount + order.plus_discount, "wallet": order.wallet_used,
               "delivery": order.delivery_fee, "total": order.total_amount, "payment": order.get_payment_method_display(),
               "status": order.get_status_display()}
    else:
        r = get_object_or_404(DealReservation.objects.select_related("shop", "customer", "deal__product"), pk=pk)
        lines = [{"name": r.deal.product.name, "qty": r.quantity, "unit": r.unit, "mrp": r.normal_unit_price, "price": r.unit_price,
                  "amount": r.total_amount}]
        doc = {"number": r.reservation_number, "date": r.completed_at or r.created_at, "shop": r.shop, "customer": r.customer,
               "lines": lines, "subtotal": r.total_amount, "savings": r.savings, "discounts": 0, "wallet": 0, "delivery": 0,
               "total": r.total_amount, "payment": "दुकान पर", "status": r.get_status_display()}
    return render(request, "share/bill.html", {"doc": doc})


def shop_poster_page(request, pk):
    """Printable A4 poster with the shop's QR code (the merchant opens it from the app and prints / saves as PDF)."""
    import segno
    from django.shortcuts import get_object_or_404
    from django.utils.safestring import mark_safe

    from apps.shops.models import Shop

    shop = get_object_or_404(Shop, pk=pk, status=Shop.Status.APPROVED)
    link = request.build_absolute_uri(f"/s/{shop.id}/")
    qr = segno.make(link, error="h").svg_inline(scale=12, dark="#0A0A0A", border=2)
    return render(request, "share/poster.html", {"shop": shop, "qr": mark_safe(qr), "link": link})


def legal_page(request, page):
    """Public policy pages, linked from the app and the Play Store listing. Have a lawyer review them before launch."""
    if page not in LEGAL_PAGES:
        raise Http404
    return render(request, f"legal/{page}.html", {
        "title": LEGAL_PAGES[page], "updated": "5 November 2026", "city": "Bharatpur",
        "contact_email": settings.SUPPORT_EMAIL, "hold_minutes": settings.RESERVATION_HOLD_MINUTES,
        "commission": settings.DEFAULT_COMMISSION_PERCENT, "complaint_hours": settings.QUALITY_COMPLAINT_HOURS,
        "reply_hours": settings.QUALITY_SHOP_REPLY_HOURS, "wallet_percent": settings.WALLET_MAX_PERCENT_OF_ORDER,
        "credits": _photo_credits() if page == "photo-credits" else [],
    })


api_v1_patterns = [
    path("auth/", include("apps.accounts.urls")),
    path("customers/", include("apps.customers.urls")),
    path("merchants/shop/", include("apps.shops.merchant_urls")),
    path("merchants/", include("apps.merchants.urls")),
    path("shops/", include("apps.shops.urls")),
    path("categories/", include("apps.categories.urls")),
    path("products/", include("apps.products.urls")),
    path("inventory/", include("apps.inventory.urls")),
    path("deals/", include("apps.deals.urls")),
    path("reservations/", include("apps.reservations.urls")),
    path("orders/", include("apps.orders.urls")),
    path("payments/", include("apps.payments.urls")),
    path("notifications/", include("apps.notifications.urls")),
    path("reviews/", include("apps.reviews.urls")),
    path("quality/", include("apps.quality.urls")),
    path("khata/", include("apps.khata.urls")),
    path("daily/", include("apps.daily.urls")),
    path("chat/", include("apps.chat.urls")),
    path("growth/", include("apps.growth.urls")),
    path("team/", include("apps.team.urls")),
    path("advertisements/", include("apps.advertisements.urls")),
    path("subscriptions/", include("apps.subscriptions.urls")),
    path("commissions/", include("apps.commissions.urls")),
    path("analytics/", include("apps.analytics.urls")),
    path("support/", include("apps.support.urls")),
    path("app/", include("apps.releases.urls")),
]

urlpatterns = [
    path("admin/dashboard/", admin_dashboard, name="admin-dashboard"),
    path("admin/reports/<str:kind>.xlsx", admin_report_download, name="admin-report-download"),
    path("admin/", admin.site.urls),
    path("health/", health_check),
    path("legal/<str:page>/", legal_page, name="legal"),
    path("d/<int:pk>/", deal_share_page, name="deal-share"),
    path("bill/<str:token>/", bill_page, name="bill"),
    path("s/<int:pk>/", shop_share_page, name="shop-share"),
    path("s/<int:pk>/poster/", shop_poster_page, name="shop-poster"),
    path("api/v1/", include(api_v1_patterns)),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
elif getattr(settings, "SERVE_MEDIA", False):
    urlpatterns += [re_path(r"^media/(?P<path>.*)$", serve, {"document_root": settings.MEDIA_ROOT})]
