from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsCustomer, IsMerchant

from . import services
from .models import DealReservation
from .serializers import (
    MerchantReservationSerializer,
    PickupSerializer,
    ReasonSerializer,
    ReservationCreateSerializer,
    ReservationSerializer,
)


def visible_reservations(user):
    """Customers see their own reservations; merchants see their shops' reservations."""
    qs = DealReservation.objects.select_related("deal__product", "shop", "customer")
    if not user.is_authenticated:  # only during API schema generation
        return qs.none()
    if user.is_customer:
        return qs.filter(customer=user)
    if user.is_merchant:
        return qs.filter(shop__merchant__user=user)
    raise PermissionDenied("Only customers and merchants have reservations.")


def serializer_for(user):
    return MerchantReservationSerializer if getattr(user, "is_merchant", False) else ReservationSerializer


class ReservationCreateView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=ReservationCreateSerializer, responses={201: ReservationSerializer})
    def post(self, request):
        serializer = ReservationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reservation = services.create_reservation(
            request.user, serializer.validated_data["deal"], serializer.validated_data["quantity"],
            serializer.validated_data.get("pickup_at"),
        )
        return Response(ReservationSerializer(reservation).data, status=status.HTTP_201_CREATED)


class ReservationListView(generics.ListAPIView):
    filterset_fields = ["status", "shop"]

    def get_queryset(self):
        return visible_reservations(self.request.user)

    def get_serializer_class(self):
        return serializer_for(self.request.user)


class ReservationDetailView(generics.RetrieveAPIView):
    def get_queryset(self):
        return visible_reservations(self.request.user)

    def get_serializer_class(self):
        return serializer_for(self.request.user)


class MerchantReservationActionView(APIView):
    """confirm / reject / complete, for the shop that owns the reservation."""

    permission_classes = [IsMerchant]
    action = None

    @extend_schema(
        request=PickupSerializer,
        responses=MerchantReservationSerializer,
        description="confirm: no body. reject: optional {reason}. complete: {pickup_code}.",
    )
    def post(self, request, pk):
        reservation = get_object_or_404(visible_reservations(request.user), pk=pk)
        if self.action == "confirm":
            reservation = services.confirm(reservation)
        elif self.action == "reject":
            body = ReasonSerializer(data=request.data)
            body.is_valid(raise_exception=True)
            reservation = services.reject(reservation, body.validated_data.get("reason", ""))
        else:
            body = PickupSerializer(data=request.data)
            body.is_valid(raise_exception=True)
            reservation = services.complete(reservation, body.validated_data["pickup_code"])
        return Response(MerchantReservationSerializer(reservation).data)


class ReservationCancelView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=ReasonSerializer, responses=ReservationSerializer)
    def post(self, request, pk):
        reservation = get_object_or_404(visible_reservations(request.user), pk=pk)
        body = ReasonSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        reservation = services.cancel(reservation, body.validated_data.get("reason", ""))
        return Response(ReservationSerializer(reservation).data)
