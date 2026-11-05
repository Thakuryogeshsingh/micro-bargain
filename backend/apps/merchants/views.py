from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import MerchantProfile
from .serializers import MerchantProfileSerializer, MerchantRegisterSerializer


class MerchantRegisterView(APIView):
    @extend_schema(request=MerchantRegisterSerializer, responses={201: MerchantProfileSerializer})
    def post(self, request):
        serializer = MerchantRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = services.register_merchant(request.user, **serializer.validated_data)
        return Response(MerchantProfileSerializer(profile).data, status=status.HTTP_201_CREATED)


class MerchantProfileView(generics.RetrieveAPIView):
    serializer_class = MerchantProfileSerializer
    permission_classes = [IsMerchant]

    def get_object(self):
        return get_object_or_404(MerchantProfile, user=self.request.user)


class MerchantDashboardView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        return Response(services.dashboard_stats(request.user))


class OnboardingView(APIView):
    """GET: onboarding checklist. POST: submit for review once every step is done."""

    permission_classes = [IsMerchant]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        return Response(services.onboarding_status(get_object_or_404(MerchantProfile, user=request.user)))

    @extend_schema(request=None, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        return Response(services.submit_onboarding(get_object_or_404(MerchantProfile, user=request.user)))


class MerchantProfileUpdateView(generics.UpdateAPIView):
    serializer_class = MerchantProfileSerializer
    permission_classes = [IsMerchant]
    http_method_names = ["patch"]

    def get_object(self):
        return get_object_or_404(MerchantProfile, user=self.request.user)
