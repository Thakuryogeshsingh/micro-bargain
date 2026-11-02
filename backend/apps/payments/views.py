from django.conf import settings
from django.http import Http404
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .models import Payment
from .serializers import CheckoutSerializer, PaymentCreateSerializer, PaymentSerializer, PaymentVerifySerializer


class PaymentCreateView(APIView):
    @extend_schema(request=PaymentCreateSerializer, responses={201: CheckoutSerializer})
    def post(self, request):
        body = PaymentCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        payment = services.create_payment(request.user, body.validated_data["purpose"], body.validated_data["id"])
        checkout = {
            "payment_id": payment.id,
            "key_id": settings.RAZORPAY_KEY_ID,
            "razorpay_order_id": payment.gateway_order_id,
            "amount": services.to_paise(payment.amount),
            "currency": payment.currency,
            "name": "Micro Bargain",
            "description": payment.get_purpose_display(),
            "prefill_contact": f"+91{request.user.phone}",
        }
        return Response(CheckoutSerializer(checkout).data, status=status.HTTP_201_CREATED)


class PaymentVerifyView(APIView):
    @extend_schema(request=PaymentVerifySerializer, responses=PaymentSerializer)
    def post(self, request):
        body = PaymentVerifySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        payment = services.verify(request.user, data["razorpay_order_id"], data["razorpay_payment_id"], data["razorpay_signature"])
        return Response(PaymentSerializer(payment).data)


class DevCompletePaymentView(APIView):
    """Development only (PAYMENT_BACKEND=fake): marks a payment paid without Razorpay, so the app's
    payment flow can be tested end to end. Returns 404 with a real payment backend."""

    @extend_schema(request=OpenApiTypes.OBJECT, responses=PaymentSerializer)
    def post(self, request):
        if settings.PAYMENT_BACKEND != "fake":
            raise Http404
        payment = get_object_or_404(request.user.payments, gateway_order_id=request.data.get("razorpay_order_id", ""))
        return Response(PaymentSerializer(services.mark_paid(payment.id, f"pay_dev{payment.id}", "test")).data)


class PaymentWebhookView(APIView):
    """Called by Razorpay, not the app. Authenticated by the X-Razorpay-Signature HMAC instead of a login."""

    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = []

    @extend_schema(request=OpenApiTypes.OBJECT, responses={200: OpenApiTypes.OBJECT})
    def post(self, request):
        result = services.handle_webhook(
            request.body, request.headers.get("X-Razorpay-Signature", ""), request.headers.get("X-Razorpay-Event-Id", "")
        )
        return Response({"status": result})


class PaymentHistoryView(generics.ListAPIView):
    serializer_class = PaymentSerializer
    filterset_fields = ["purpose", "status"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Payment.objects.none()
        return self.request.user.payments.select_related("order").prefetch_related("refunds")


class PaymentDetailView(generics.RetrieveAPIView):
    serializer_class = PaymentSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Payment.objects.none()
        return self.request.user.payments.select_related("order").prefetch_related("refunds")
