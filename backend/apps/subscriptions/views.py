from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import MerchantSubscription, Plan
from .serializers import PlanSerializer, SubscribeSerializer, SubscriptionSerializer


class PlanListView(generics.ListAPIView):
    serializer_class = PlanSerializer
    permission_classes = [AllowAny]
    pagination_class = None
    queryset = Plan.objects.filter(is_active=True)


class CurrentPlanView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        merchant = request.user.merchant_profile
        subscription = services.active_subscription(merchant)
        return Response({
            "plan": PlanSerializer(services.current_plan(merchant)).data,
            "subscription": SubscriptionSerializer(subscription).data if subscription else None,
        })


class SubscribeView(APIView):
    """Creates an unpaid subscription. Pay for it with POST /payments/create/ {purpose: "subscription", id}."""

    permission_classes = [IsMerchant]

    @extend_schema(request=SubscribeSerializer, responses={201: SubscriptionSerializer})
    def post(self, request):
        body = SubscribeSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        subscription = services.subscribe(request.user.merchant_profile, body.validated_data["plan"], body.validated_data["months"])
        return Response(SubscriptionSerializer(subscription).data, status=status.HTTP_201_CREATED)


class SubscriptionHistoryView(generics.ListAPIView):
    serializer_class = SubscriptionSerializer
    permission_classes = [IsMerchant]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return MerchantSubscription.objects.none()
        return MerchantSubscription.objects.filter(merchant__user=self.request.user).select_related("plan")
