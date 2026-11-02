from django.db.models import F
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import Inventory, InventoryMovement
from .serializers import AdjustSerializer, InventorySerializer, MovementSerializer


def merchant_inventory(user):
    if not user.is_authenticated:  # only during API schema generation
        return Inventory.objects.none()
    return Inventory.objects.filter(shop__merchant__user=user).select_related("product")


class InventoryListView(generics.ListAPIView):
    """?low_stock=true lists only items at or below their threshold."""

    serializer_class = InventorySerializer
    permission_classes = [IsMerchant]
    search_fields = ["product__name"]

    def get_queryset(self):
        qs = merchant_inventory(self.request.user)
        if self.request.query_params.get("low_stock") == "true":
            qs = qs.filter(quantity_on_hand__lte=F("low_stock_threshold"))
        return qs


class InventoryAdjustView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=AdjustSerializer, responses=InventorySerializer)
    def post(self, request):
        body = AdjustSerializer(data=request.data, context={"request": request})
        body.is_valid(raise_exception=True)
        inventory = services.adjust(request.user, **body.validated_data)
        return Response(InventorySerializer(inventory).data)


class MovementListView(generics.ListAPIView):
    serializer_class = MovementSerializer
    permission_classes = [IsMerchant]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return InventoryMovement.objects.none()
        return get_object_or_404(merchant_inventory(self.request.user), pk=self.kwargs["pk"]).movements.all()
