from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.orders.models import Order
from apps.reservations.models import DealReservation
from common.permissions import IsCustomer, IsMerchant

from . import services
from .models import Review
from .serializers import ReplySerializer, ReviewCreateSerializer, ReviewSerializer


class ReviewCreateView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=ReviewCreateSerializer, responses={201: ReviewSerializer})
    def post(self, request):
        body = ReviewCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        # Scoped to the customer: someone else's reservation id is a 404.
        reservation = order = None
        if "reservation" in data:
            reservation = get_object_or_404(DealReservation.objects.filter(customer=request.user), pk=data["reservation"])
        else:
            order = get_object_or_404(Order.objects.filter(customer=request.user), pk=data["order"])
        review = services.create_review(request.user, data["rating"], data.get("comment", ""), reservation, order)
        return Response(ReviewSerializer(review).data, status=status.HTTP_201_CREATED)


class ShopReviewsView(generics.ListAPIView):
    serializer_class = ReviewSerializer
    permission_classes = [AllowAny]
    filterset_fields = ["rating"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Review.objects.none()
        return Review.objects.filter(shop_id=self.kwargs["shop_id"], is_hidden=False).select_related("customer")


class MyReviewsView(generics.ListAPIView):
    """Customers: reviews they wrote. Merchants: reviews of their shops."""

    serializer_class = ReviewSerializer

    def get_queryset(self):
        user = self.request.user
        if not user.is_authenticated:  # only during API schema generation
            return Review.objects.none()
        qs = Review.objects.select_related("customer")
        return qs.filter(shop__merchant__user=user) if user.is_merchant else qs.filter(customer=user)


class ReplyView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=ReplySerializer, responses=ReviewSerializer)
    def post(self, request, pk):
        review = get_object_or_404(Review.objects.filter(shop__merchant__user=request.user), pk=pk)
        body = ReplySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        return Response(ReviewSerializer(services.reply(review, body.validated_data["reply"])).data)
