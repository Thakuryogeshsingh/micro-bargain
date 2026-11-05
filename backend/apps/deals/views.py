from django.db.models import F, Q
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import Deal
from .serializers import (
    DealCreateSerializer,
    DealSerializer,
    DealUpdateSerializer,
    MerchantDealSerializer,
    NearbyDealsQuerySerializer,
    StockUpdateSerializer,
)


def merchant_deals(user):
    if not user.is_authenticated:  # only during API schema generation
        return Deal.objects.none()
    # Scoping by owner means another merchant's deal id returns 404.
    return (
        Deal.objects.filter(shop__merchant__user=user)
        .select_related("shop", "product", "product__category")
        .prefetch_related("product__images")
    )


# ---------- merchant ----------

class DealCreateView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=DealCreateSerializer, responses={201: MerchantDealSerializer})
    def post(self, request):
        serializer = DealCreateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        deal = services.create_deal(request.user, **serializer.validated_data)
        return Response(MerchantDealSerializer(deal, context={"request": request}).data, status=status.HTTP_201_CREATED)


class MerchantDealListView(generics.ListAPIView):
    serializer_class = MerchantDealSerializer
    permission_classes = [IsMerchant]
    filterset_fields = ["status", "shop", "product"]
    ordering_fields = ["created_at", "expires_at", "offer_price", "discount_percent"]

    def get_queryset(self):
        return merchant_deals(self.request.user)


class DealUpdateView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=DealUpdateSerializer, responses=MerchantDealSerializer)
    def patch(self, request, pk):
        deal = get_object_or_404(merchant_deals(request.user), pk=pk)
        serializer = DealUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        deal = services.update_deal(deal, request.user, **serializer.validated_data)
        return Response(MerchantDealSerializer(deal, context={"request": request}).data)


class DealActionView(APIView):
    """POST /deals/{id}/<action>/ for publish, pause, sold-out, end, duplicate, update-stock."""

    permission_classes = [IsMerchant]
    action = None

    @extend_schema(
        request=StockUpdateSerializer,
        responses=MerchantDealSerializer,
        description="Body is only needed for update-stock. duplicate returns 201 with the new draft.",
    )
    def post(self, request, pk):
        deal = get_object_or_404(merchant_deals(request.user), pk=pk)
        if self.action == "publish":
            deal = services.publish_deal(deal, request.user)
        elif self.action == "duplicate":
            deal = services.duplicate_deal(deal, request.user)
        elif self.action == "update-stock":
            serializer = StockUpdateSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            deal = services.update_stock(deal, request.user, serializer.validated_data["quantity_total"])
        else:
            new_status = {"pause": Deal.Status.PAUSED, "sold-out": Deal.Status.SOLD_OUT, "end": Deal.Status.ENDED}
            deal = services.change_status(deal, request.user, new_status[self.action])
        code = status.HTTP_201_CREATED if self.action == "duplicate" else status.HTTP_200_OK
        return Response(MerchantDealSerializer(deal, context={"request": request}).data, status=code)


class RepeatYesterdayView(APIView):
    """POST /deals/repeat-yesterday/: put yesterday's deals live again in one tap."""

    permission_classes = [IsMerchant]

    @extend_schema(request=None, responses={200: OpenApiTypes.OBJECT})
    def post(self, request):
        created, skipped = services.repeat_yesterday(request.user)
        return Response({"created": len(created), "skipped": skipped})


class PriceSuggestionView(APIView):
    """GET /deals/price-suggestion/?product=<id>: suggested offer price for a quick sale."""

    permission_classes = [IsMerchant]

    @extend_schema(parameters=[OpenApiParameter("product", int)], responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        from apps.products.models import Product

        product = get_object_or_404(Product.objects.filter(shop__merchant__user=request.user), pk=request.query_params.get("product") or 0)
        return Response(services.price_suggestion(product))


# ---------- customer ----------

@extend_schema(parameters=[NearbyDealsQuerySerializer])
class NearbyDealsView(generics.ListAPIView):
    serializer_class = DealSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Deal.objects.none()
        query = NearbyDealsQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        return services.nearby_deals(**query.validated_data)


class BoughtTogetherView(generics.ListAPIView):
    """GET /deals/{id}/together/: other live deals at the same shop that customers buy with this one."""

    serializer_class = DealSerializer
    permission_classes = [AllowAny]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Deal.objects.none()
        deal = get_object_or_404(Deal, pk=self.kwargs["pk"])
        return services.bought_together(deal)


class ShopDealsView(generics.ListAPIView):
    serializer_class = DealSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Deal.objects.none()
        return services.live_deals().filter(shop_id=self.kwargs["shop_id"]).order_by("expires_at")


class DealDetailView(generics.RetrieveAPIView):
    """Anyone can open a deal that is live or recently closed; owners can also see drafts."""

    permission_classes = [AllowAny]

    def get_queryset(self):
        visible = ~Q(status=Deal.Status.DRAFT)
        if self.request.user.is_authenticated:
            visible |= Q(shop__merchant__user=self.request.user)
        return (
            Deal.objects.filter(visible, shop__status="approved")
            .select_related("shop", "product", "product__category")
            .prefetch_related("product__images")
        )

    def get_serializer_class(self):
        deal = getattr(self, "_deal", None)
        if deal and self.request.user.is_authenticated and deal.shop.merchant.user_id == self.request.user.id:
            return MerchantDealSerializer
        return DealSerializer

    def get_object(self):
        self._deal = super().get_object()
        if self._deal.shop.merchant.user_id != self.request.user.id:
            Deal.objects.filter(pk=self._deal.pk).update(view_count=F("view_count") + 1)
        return self._deal
