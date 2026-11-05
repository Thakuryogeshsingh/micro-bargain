from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import generics, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.orders.models import Order
from apps.reservations.models import DealReservation
from common.permissions import IsCustomer, IsMerchant

from . import services
from .models import QualityComplaint


class ComplaintSerializer(serializers.ModelSerializer):
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    reason_label = serializers.CharField(source="get_reason_display", read_only=True)
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    reference = serializers.CharField(read_only=True)

    class Meta:
        model = QualityComplaint
        fields = [
            "id", "shop", "shop_name", "reservation", "order", "reference", "reason", "reason_label", "description", "photo",
            "amount_paid", "status", "refund_amount", "shop_note", "admin_note", "customer_name", "created_at", "resolved_at",
        ]


class ComplaintCreateSerializer(serializers.Serializer):
    reservation = serializers.IntegerField(required=False)
    order = serializers.IntegerField(required=False)
    reason = serializers.ChoiceField(choices=QualityComplaint.Reason.choices)
    description = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    photo = serializers.ImageField()

    def validate(self, attrs):
        if ("reservation" in attrs) == ("order" in attrs):
            raise serializers.ValidationError("Send either reservation or order.")
        return attrs


class RespondSerializer(serializers.Serializer):
    accept = serializers.BooleanField()
    amount = serializers.DecimalField(max_digits=10, decimal_places=2, required=False)
    note = serializers.CharField(required=False, allow_blank=True, max_length=500)


class ComplaintListCreateView(APIView):
    """Customers: their complaints (GET) and a new complaint (POST, multipart with a photo)."""

    permission_classes = [IsCustomer]

    @extend_schema(responses=ComplaintSerializer(many=True))
    def get(self, request):
        qs = QualityComplaint.objects.filter(customer=request.user).select_related("shop", "reservation", "order", "customer")
        return Response(ComplaintSerializer(qs, many=True, context={"request": request}).data)

    @extend_schema(request=ComplaintCreateSerializer, responses={201: ComplaintSerializer})
    def post(self, request):
        body = ComplaintCreateSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        reservation = order = None
        if "reservation" in data:
            reservation = get_object_or_404(DealReservation.objects.filter(customer=request.user), pk=data["reservation"])
        else:
            order = get_object_or_404(Order.objects.filter(customer=request.user), pk=data["order"])
        complaint = services.create_complaint(
            request.user, data["reason"], data["photo"], data.get("description", ""), reservation, order
        )
        return Response(ComplaintSerializer(complaint, context={"request": request}).data, status=status.HTTP_201_CREATED)


class ShopComplaintsView(generics.ListAPIView):
    """Merchants: complaints about their shop, open ones first."""

    permission_classes = [IsMerchant]
    serializer_class = ComplaintSerializer
    filterset_fields = ["status"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return QualityComplaint.objects.none()
        return (
            QualityComplaint.objects.filter(shop__merchant__user=self.request.user)
            .select_related("shop", "reservation", "order", "customer")
            .order_by("-status", "-created_at")  # "open" sorts before "disputed"/"refunded"/"rejected"
        )


class RespondView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=RespondSerializer, responses=ComplaintSerializer)
    def post(self, request, pk):
        complaint = get_object_or_404(QualityComplaint.objects.filter(shop__merchant__user=request.user), pk=pk)
        body = RespondSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data
        complaint = services.shop_respond(complaint, request.user, data["accept"], data.get("amount"), data.get("note", ""))
        return Response(ComplaintSerializer(complaint, context={"request": request}).data)
