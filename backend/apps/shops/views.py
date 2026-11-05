from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import generics, serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.merchants.models import MerchantProfile
from common.permissions import IsCustomer, IsMerchant

from . import services
from .models import FavoriteShop, Shop, ShopDocument
from .serializers import (
    NearbyQuerySerializer,
    PublicShopSerializer,
    ShopDocumentSerializer,
    ShopSerializer,
    ShopWriteSerializer,
)


def _favorite_ids(request):
    if request.user.is_authenticated:
        return set(request.user.favorite_shops.values_list("shop_id", flat=True))
    return None


# ---------- merchant: own shops (mounted under /merchants/shop/) ----------

class MerchantShopMixin:
    permission_classes = [IsMerchant]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Shop.objects.none()
        # Scoping by owner means another merchant's shop id returns 404.
        return Shop.objects.filter(merchant__user=self.request.user).select_related("category")


class ShopCreateView(MerchantShopMixin, APIView):
    @extend_schema(request=ShopWriteSerializer, responses={201: ShopSerializer})
    def post(self, request):
        merchant = get_object_or_404(MerchantProfile, user=request.user)
        serializer = ShopWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        shop = services.create_shop(merchant, **serializer.validated_data)
        return Response(ShopSerializer(shop).data, status=status.HTTP_201_CREATED)


class ShopListView(MerchantShopMixin, generics.ListAPIView):
    serializer_class = ShopSerializer
    pagination_class = None


class ShopUpdateView(MerchantShopMixin, APIView):
    @extend_schema(request=ShopWriteSerializer, responses=ShopSerializer)
    def patch(self, request, pk):
        shop = get_object_or_404(self.get_queryset(), pk=pk)
        serializer = ShopWriteSerializer(shop, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        shop = services.update_shop(shop, **serializer.validated_data)
        return Response(ShopSerializer(shop).data)


class ShopDocumentListCreateView(MerchantShopMixin, generics.ListCreateAPIView):
    serializer_class = ShopDocumentSerializer
    pagination_class = None

    def get_shop(self):
        return get_object_or_404(MerchantShopMixin.get_queryset(self), pk=self.kwargs["pk"])

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return ShopDocument.objects.none()
        return self.get_shop().documents.all()

    def perform_create(self, serializer):
        serializer.save(shop=self.get_shop())


# ---------- customer-facing ----------

@extend_schema(parameters=[NearbyQuerySerializer])
class NearbyShopsView(generics.ListAPIView):
    serializer_class = PublicShopSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Shop.objects.none()
        query = NearbyQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        return services.nearby_shops(
            query.validated_data["latitude"],
            query.validated_data["longitude"],
            query.validated_data["radius"],
            query.validated_data.get("category"),
        )

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "favorite_ids": _favorite_ids(self.request)}


class LeaderboardView(APIView):
    """GET /shops/leaderboard/?latitude&longitude: this week's top-saving shops nearby."""

    permission_classes = [AllowAny]

    @extend_schema(parameters=[NearbyQuerySerializer], responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        query = NearbyQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        rows = services.leaderboard(query.validated_data["latitude"], query.validated_data["longitude"])
        return Response([
            {"rank": i + 1, "savings": r["savings"], "purchases": r["purchases"],
             "shop": PublicShopSerializer(r["shop"], context={"request": request}).data}
            for i, r in enumerate(rows)
        ])


class ShopDetailView(generics.RetrieveAPIView):
    serializer_class = PublicShopSerializer
    permission_classes = [AllowAny]
    def get_queryset(self):
        # Built per request: the deal stats depend on the current time.
        return services.with_deal_stats(Shop.objects.filter(status=Shop.Status.APPROVED).select_related("category"))

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "favorite_ids": _favorite_ids(self.request)}


class FavoriteShopView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=None, responses={201: inline_serializer("Favorite", {"is_favorite": serializers.BooleanField()})})
    def post(self, request, pk):
        shop = get_object_or_404(Shop, pk=pk, status=Shop.Status.APPROVED)
        FavoriteShop.objects.get_or_create(user=request.user, shop=shop)
        return Response({"is_favorite": True}, status=status.HTTP_201_CREATED)

    @extend_schema(responses={204: None})
    def delete(self, request, pk):
        FavoriteShop.objects.filter(user=request.user, shop_id=pk).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class FavoriteShopListView(generics.ListAPIView):
    serializer_class = PublicShopSerializer
    permission_classes = [IsCustomer]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Shop.objects.none()
        return Shop.objects.filter(
            favorited_by__user=self.request.user, status=Shop.Status.APPROVED
        ).select_related("category")

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "favorite_ids": _favorite_ids(self.request)}
