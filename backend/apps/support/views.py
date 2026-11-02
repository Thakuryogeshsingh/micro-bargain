from django.db.models import Q
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.orders.models import Order
from apps.reservations.models import DealReservation

from . import services
from .models import Complaint
from .serializers import ComplaintCreateSerializer, ComplaintSerializer, MessageSerializer


def own_complaints(user):
    if not user.is_authenticated:  # only during API schema generation
        return Complaint.objects.none()
    return user.complaints.prefetch_related("messages")


class ComplaintListCreateView(APIView):
    @extend_schema(responses=ComplaintSerializer(many=True))
    def get(self, request):
        return Response(ComplaintSerializer(own_complaints(request.user), many=True).data)

    @extend_schema(request=ComplaintCreateSerializer, responses={201: ComplaintSerializer})
    def post(self, request):
        body = ComplaintCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        # The linked order/reservation must involve this user (as customer or as the shop).
        mine = Q(customer=request.user) | Q(shop__merchant__user=request.user)
        order = get_object_or_404(Order.objects.filter(mine), pk=data["order"]) if "order" in data else None
        reservation = (
            get_object_or_404(DealReservation.objects.filter(mine), pk=data["reservation"]) if "reservation" in data else None
        )
        complaint = services.create_complaint(
            request.user, data["category"], data["subject"], data["message"], order, reservation
        )
        return Response(ComplaintSerializer(complaint).data, status=status.HTTP_201_CREATED)


class ComplaintDetailView(generics.RetrieveAPIView):
    serializer_class = ComplaintSerializer

    def get_queryset(self):
        return own_complaints(self.request.user)


class ComplaintMessageView(APIView):
    @extend_schema(request=MessageSerializer, responses=ComplaintSerializer)
    def post(self, request, pk):
        complaint = get_object_or_404(own_complaints(request.user), pk=pk)
        body = MessageSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        services.add_user_message(complaint, request.user, body.validated_data["message"])
        return Response(ComplaintSerializer(own_complaints(request.user).get(pk=pk)).data)
