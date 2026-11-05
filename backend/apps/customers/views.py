from django.conf import settings
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsCustomer

from . import services
from .models import Address, CustomerProfile
from .serializers import AddressSerializer, CustomerProfileSerializer


class CustomerProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = CustomerProfileSerializer
    permission_classes = [IsCustomer]
    http_method_names = ["get", "patch"]

    def get_object(self):
        profile, _ = CustomerProfile.objects.get_or_create(user=self.request.user)
        return profile


class AddressListCreateView(generics.ListCreateAPIView):
    serializer_class = AddressSerializer
    permission_classes = [IsCustomer]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Address.objects.none()
        return self.request.user.addresses.all()

    def perform_create(self, serializer):
        services.save_address(serializer, self.request.user)


class AddressDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = AddressSerializer
    permission_classes = [IsCustomer]
    http_method_names = ["get", "patch", "delete"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Address.objects.none()
        # Filtering by owner means other users' addresses return 404.
        return self.request.user.addresses.all()

    def perform_update(self, serializer):
        services.save_address(serializer, self.request.user)


class ImpactView(APIView):
    """GET /customers/impact/: money saved and food rescued (for the profile badge)."""

    permission_classes = [IsCustomer]

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        return Response(services.impact(request.user))


class PlusView(APIView):
    """GET: Bargain Plus status and price. POST: start a purchase (then pay with purpose "membership")."""

    permission_classes = [IsCustomer]

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        current = services.active_plus(request.user)
        return Response({
            "active": current is not None,
            "ends_at": current.ends_at if current else None,
            "price": settings.PLUS_PRICE_RUPEES,
            "days": settings.PLUS_DAYS,
            "extra_percent": settings.PLUS_EXTRA_PERCENT,
            "extra_cap": settings.PLUS_EXTRA_CAP_RUPEES,
        })

    @extend_schema(request=None, responses={201: OpenApiTypes.OBJECT})
    def post(self, request):
        membership = services.buy_plus(request.user)
        return Response({"id": membership.id, "amount": membership.amount}, status=201)


class ReferralView(APIView):
    """GET: my code, share message and how many friends joined. POST {code}: apply a friend's code."""

    permission_classes = [IsCustomer]

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        code = services.referral_code(request.user)
        profile = request.user.customer_profile
        amount = settings.REFERRAL_REWARD_RUPEES
        return Response({
            "code": code,
            "reward_amount": amount,
            "min_order": settings.REFERRAL_REWARD_MIN_ORDER,
            "friends_joined": profile.user.referrals.count(),
            "friends_rewarded": CustomerProfile.objects.filter(referred_by=request.user, referral_rewarded_at__isnull=False).count(),
            "referred_by_applied": profile.referred_by_id is not None,
            "share_text": (
                f"Micro Bargain ऐप पर पास की दुकानों की ताज़ा डील सस्ते में मिलती हैं! "
                f"मेरा कोड {code} डालें — पहली खरीद पर हम दोनों को ₹{amount} का कूपन मिलेगा।"
            ),
        })

    @extend_schema(request=OpenApiTypes.OBJECT, responses={200: OpenApiTypes.OBJECT})
    def post(self, request):
        code = serializers.CharField(max_length=10).run_validation(request.data.get("code"))
        referrer = services.apply_referral(request.user, code)
        return Response({"applied": True, "referrer": referrer.name or "दोस्त"})
