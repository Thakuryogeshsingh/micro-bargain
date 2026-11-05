"""Daily subscriptions (milk, bread...): customers subscribe, shops see today's list and mark deliveries."""
from datetime import date

from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.notifications import services as notifications
from apps.products.models import Product
from apps.shops.models import Shop
from common.exceptions import BusinessRuleError
from common.permissions import IsCustomer, IsMerchant

from .models import DailyDelivery, DailyOrder


def _month_total(daily):
    today = timezone.localdate()
    return daily.deliveries.filter(status=DailyDelivery.Status.DELIVERED, date__year=today.year, date__month=today.month).aggregate(
        s=Sum("amount"))["s"] or 0


class DailySerializer(serializers.ModelSerializer):
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    shop_phone = serializers.CharField(source="shop.phone", read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)
    unit = serializers.CharField(source="product.unit", read_only=True)
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    customer_phone = serializers.CharField(source="customer.phone", read_only=True)
    address_text = serializers.SerializerMethodField()
    month_total = serializers.SerializerMethodField()

    class Meta:
        model = DailyOrder
        fields = [
            "id", "shop", "shop_name", "shop_phone", "product", "product_name", "unit", "quantity", "price", "weekdays", "slot",
            "address", "address_text", "note", "status", "paused_until", "customer_name", "customer_phone", "month_total", "created_at",
        ]
        read_only_fields = ["id", "shop", "price", "status", "paused_until", "created_at"]

    def get_address_text(self, obj) -> str:
        a = obj.address
        return ", ".join(p for p in [a.address_line, a.landmark, a.city] if p) if a else ""

    def get_month_total(self, obj) -> str:
        return f"{_month_total(obj):.2f}"


class ShopProductsView(APIView):
    """GET /daily/products/?shop=<id>: what can be subscribed to at a shop."""

    permission_classes = [AllowAny]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        shop = get_object_or_404(Shop, pk=request.query_params.get("shop") or 0, status=Shop.Status.APPROVED)
        products = Product.objects.filter(shop=shop, is_active=True).prefetch_related("images").order_by("name")
        return Response([
            {"id": p.id, "name": p.name, "unit": p.unit, "price": p.standard_price,
             "image": request.build_absolute_uri(p.images.all()[0].image.url) if p.images.all() else None}
            for p in products
        ])


class MyDailyView(APIView):
    """Customers: GET their subscriptions, POST a new one."""

    permission_classes = [IsCustomer]

    @extend_schema(responses=DailySerializer(many=True))
    def get(self, request):
        qs = request.user.daily_orders.exclude(status=DailyOrder.Status.CANCELLED).select_related("shop", "product", "address")
        return Response(DailySerializer(qs, many=True).data)

    @extend_schema(request=DailySerializer, responses={201: DailySerializer})
    def post(self, request):
        body = DailySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        product = data["product"]
        if not product.is_active or product.shop.status != Shop.Status.APPROVED:
            raise BusinessRuleError("This item is not available.", "unavailable")
        if "1" not in data.get("weekdays", "1111111"):
            raise BusinessRuleError("Choose at least one day.", "no_days")
        address = data.get("address")
        if address is not None and address.user_id != request.user.id:
            raise BusinessRuleError("Choose one of your addresses.", "invalid_address")
        if DailyOrder.objects.filter(customer=request.user, product=product).exclude(status=DailyOrder.Status.CANCELLED).exists():
            raise BusinessRuleError("You already subscribe to this item.", "duplicate")
        daily = body.save(customer=request.user, shop=product.shop, price=product.standard_price)
        notifications.notify(
            product.shop.merchant.user, notifications.Kind.DAILY_ORDER, "नई रोज़ाना डिलीवरी 🥛",
            f"{request.user.name or request.user.phone}: {product.name} × {daily.quantity} ({'सुबह' if daily.slot == 'morning' else 'शाम'})",
            data={"daily_id": str(daily.id)},
        )
        return Response(DailySerializer(daily).data, status=status.HTTP_201_CREATED)


class DailyStatusView(APIView):
    """POST /daily/<id>/status/ {status: active|paused|cancelled, paused_until?}"""

    permission_classes = [IsCustomer]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=DailySerializer)
    def post(self, request, pk):
        daily = get_object_or_404(request.user.daily_orders, pk=pk)
        new = request.data.get("status")
        if new not in DailyOrder.Status.values:
            raise BusinessRuleError("Unknown status.", "invalid_status")
        daily.status = new
        daily.paused_until = None
        if new == DailyOrder.Status.PAUSED and request.data.get("paused_until"):
            daily.paused_until = date.fromisoformat(request.data["paused_until"])
        daily.save(update_fields=["status", "paused_until", "updated_at"])
        return Response(DailySerializer(daily).data)


class ShopDayView(APIView):
    """Merchants: GET /daily/shop/?date=YYYY-MM-DD - who gets what today, and what is already delivered."""

    permission_classes = [IsMerchant]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        day = date.fromisoformat(request.query_params["date"]) if request.query_params.get("date") else timezone.localdate()
        qs = (DailyOrder.objects.filter(shop__merchant__user=request.user)
              .exclude(status=DailyOrder.Status.CANCELLED).select_related("customer", "product", "address", "shop"))
        done = {d.daily_id: d.status for d in DailyDelivery.objects.filter(daily__in=qs, date=day)}
        rows = [{**DailySerializer(d).data, "delivery": done.get(d.id)} for d in qs if d.due_on(day)]
        return Response({"date": day, "count": len(rows), "items": rows, "all_subscribers": qs.count()})


class DeliverView(APIView):
    """Merchants: POST /daily/shop/<id>/deliver/ {date?, delivered: bool}"""

    permission_classes = [IsMerchant]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        daily = get_object_or_404(DailyOrder.objects.filter(shop__merchant__user=request.user), pk=pk)
        day = date.fromisoformat(request.data["date"]) if request.data.get("date") else timezone.localdate()
        delivered = bool(request.data.get("delivered", True))
        DailyDelivery.objects.update_or_create(daily=daily, date=day, defaults={
            "status": DailyDelivery.Status.DELIVERED if delivered else DailyDelivery.Status.SKIPPED,
            "quantity": daily.quantity if delivered else 0,
            "amount": daily.quantity * daily.price if delivered else 0,
        })
        return Response({"id": daily.id, "date": day, "delivered": delivered, "month_total": f"{_month_total(daily):.2f}"})
