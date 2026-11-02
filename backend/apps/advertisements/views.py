from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import Advertisement
from .serializers import AdCreateSerializer, AdvertisementSerializer, BannerQuerySerializer, BannerSerializer


class AdCreateView(APIView):
    """Creates an unpaid promotion. Pay with POST /payments/create/ {purpose: "advertisement", id}."""

    permission_classes = [IsMerchant]

    @extend_schema(request=AdCreateSerializer, responses={201: AdvertisementSerializer})
    def post(self, request):
        body = AdCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        ad = services.create_ad(request.user, **body.validated_data)
        return Response(AdvertisementSerializer(ad, context={"request": request}).data, status=status.HTTP_201_CREATED)


class MerchantAdListView(generics.ListAPIView):
    serializer_class = AdvertisementSerializer
    permission_classes = [IsMerchant]
    filterset_fields = ["status", "placement"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Advertisement.objects.none()
        return Advertisement.objects.filter(shop__merchant__user=self.request.user)


@extend_schema(parameters=[BannerQuerySerializer])
class BannerListView(generics.ListAPIView):
    serializer_class = BannerSerializer
    permission_classes = [AllowAny]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Advertisement.objects.none()
        query = BannerQuerySerializer(data=self.request.query_params)
        query.is_valid(raise_exception=True)
        return services.banners_near(**query.validated_data)


class AdClickView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(request=None, responses={204: None})
    def post(self, request, pk):
        services.record_click(pk)
        return Response(status=status.HTTP_204_NO_CONTENT)
