from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.reservations.serializers import PickupSerializer, ReasonSerializer
from apps.shops.models import Shop
from apps.notifications import services as notifications
from apps.team.models import ShopStaff, staff_job
from common.permissions import IsCustomer, IsMerchant, IsShopWorker

from . import services
from .models import Coupon, Order
from .serializers import CouponCheckSerializer, OfferSerializer, MerchantOrderSerializer, OrderCreateSerializer, OrderSerializer


def visible_orders(user):
    """Customers see their own orders; merchants see their shops' orders."""
    qs = Order.objects.select_related("shop", "customer", "coupon").prefetch_related("items")
    if not user.is_authenticated:  # only during API schema generation
        return qs.none()
    if user.is_customer:
        return qs.filter(customer=user)
    if user.is_merchant:
        return qs.filter(shop__merchant__user=user)
    if user.is_shop_staff:
        job = staff_job(user)
        if job is None:
            return qs.none()
        qs = qs.filter(shop=job.shop)
        return qs.filter(delivery_partner=user) if job.kind == ShopStaff.Kind.DELIVERY else qs
    raise PermissionDenied("Only customers and merchants have orders.")


def serializer_for(user):
    return MerchantOrderSerializer if (getattr(user, "is_merchant", False) or getattr(user, "is_shop_staff", False)) else OrderSerializer


class OrderCreateView(APIView):
    """Online orders come back as pending_payment: then call POST /payments/create/ {purpose: "order", id}."""

    permission_classes = [IsCustomer]

    @extend_schema(request=OrderCreateSerializer, responses={201: OrderSerializer})
    def post(self, request):
        body = OrderCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        address = None
        if "address" in data:
            address = get_object_or_404(request.user.addresses.all(), pk=data["address"])
        order = services.create_order(
            request.user, data["items"], data["fulfilment"], data["payment_method"], address,
            data.get("coupon_code", ""), data.get("note", ""), data.get("use_wallet", False),
        )
        return Response(OrderSerializer(order).data, status=status.HTTP_201_CREATED)


class OffersView(APIView):
    """GET /orders/offers/?shop=<id>: coupons this customer can use now (all shops, or one shop)."""

    permission_classes = [IsCustomer]

    @extend_schema(responses=OfferSerializer(many=True))
    def get(self, request):
        shop = request.query_params.get("shop")
        offers = services.available_offers(request.user, int(shop) if shop and shop.isdigit() else None)
        return Response(OfferSerializer(offers, many=True).data)


class CouponCheckView(APIView):
    """Preview a coupon on the cart screen before placing the order."""

    permission_classes = [IsCustomer]

    @extend_schema(request=CouponCheckSerializer, responses={200: OpenApiTypes.OBJECT})
    def post(self, request):
        body = CouponCheckSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        coupon = get_object_or_404(Coupon, code=data["code"].strip().upper())
        shop = get_object_or_404(Shop, pk=data["shop"])
        discount = services.coupon_discount(coupon, request.user, shop, data["subtotal"])
        return Response({"code": coupon.code, "discount": discount, "description": coupon.description})


class OrderListView(generics.ListAPIView):
    filterset_fields = ["status", "fulfilment", "payment_status"]

    def get_queryset(self):
        return visible_orders(self.request.user)

    def get_serializer_class(self):
        return serializer_for(self.request.user)


class OrderDetailView(generics.RetrieveAPIView):
    def get_queryset(self):
        return visible_orders(self.request.user)

    def get_serializer_class(self):
        return serializer_for(self.request.user)


class MerchantOrderActionView(APIView):
    """accept / ready / complete / reject for the shop that owns the order (delivery staff: complete only)."""

    permission_classes = [IsShopWorker]
    action = None

    @extend_schema(
        request=PickupSerializer, responses=MerchantOrderSerializer,
        description="accept, ready: no body. complete: {pickup_code}. reject: {reason}.",
    )
    def post(self, request, pk):
        order = get_object_or_404(visible_orders(request.user), pk=pk)
        job = staff_job(request.user) if request.user.is_shop_staff else None
        if job is not None and job.kind == ShopStaff.Kind.DELIVERY and self.action != "complete":
            raise PermissionDenied("Delivery staff can only complete their deliveries.")
        if self.action == "accept":
            order = services.accept(order)
        elif self.action == "ready":
            order = services.mark_ready(order)
        elif self.action == "complete":
            body = PickupSerializer(data=request.data)
            body.is_valid(raise_exception=True)
            order = services.complete(order, body.validated_data["pickup_code"])
        else:
            body = ReasonSerializer(data=request.data)
            body.is_valid(raise_exception=True)
            order = services.cancel_by_shop(order, body.validated_data.get("reason", ""))
        return Response(MerchantOrderSerializer(order).data)


class AssignDeliveryView(APIView):
    """Shop: POST {staff} to give a delivery order to one of its delivery people."""

    permission_classes = [IsShopWorker]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=MerchantOrderSerializer)
    def post(self, request, pk):
        order = get_object_or_404(visible_orders(request.user), pk=pk)
        partner = get_object_or_404(ShopStaff.objects.filter(shop=order.shop, kind=ShopStaff.Kind.DELIVERY, is_active=True),
                                    pk=request.data.get("staff") or 0)
        order.delivery_partner = partner.user
        order.save(update_fields=["delivery_partner", "updated_at"])
        notifications.notify(partner.user, notifications.Kind.DELIVERY, f"🛵 नई डिलीवरी: {order.order_number}",
                             order.delivery_address[:120], data={"order_id": str(order.id)})
        return Response(MerchantOrderSerializer(order).data)


class RiderLocationView(APIView):
    """Delivery person: POST {latitude, longitude} every few seconds while out for delivery."""

    permission_classes = [IsShopWorker]

    @extend_schema(request=OpenApiTypes.OBJECT, responses={204: None})
    def post(self, request, pk):
        from decimal import Decimal

        from django.utils import timezone

        from common.validators import validate_coordinates

        order = get_object_or_404(Order.objects.filter(delivery_partner=request.user), pk=pk)
        lat, lng = Decimal(str(request.data.get("latitude"))), Decimal(str(request.data.get("longitude")))
        validate_coordinates(lat, lng)
        Order.objects.filter(pk=order.pk).update(rider_latitude=round(lat, 6), rider_longitude=round(lng, 6), rider_updated_at=timezone.now())
        return Response(status=204)


class OrderCancelView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=ReasonSerializer, responses=OrderSerializer)
    def post(self, request, pk):
        order = get_object_or_404(visible_orders(request.user), pk=pk)
        body = ReasonSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        order = services.cancel_by_customer(order, body.validated_data.get("reason", ""))
        return Response(OrderSerializer(order).data)
