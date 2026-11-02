from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import Commission
from .serializers import CommissionSerializer


class MerchantCommissionListView(generics.ListAPIView):
    serializer_class = CommissionSerializer
    permission_classes = [IsMerchant]
    filterset_fields = ["status"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Commission.objects.none()
        return Commission.objects.filter(shop__merchant__user=self.request.user).select_related("order", "reservation")


class MerchantCommissionSummaryView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        shop_ids = list(request.user.merchant_profile.shops.values_list("id", flat=True))
        return Response(services.summary(shop_ids))
