"""Udhaar khata: the shop's credit ledger. Balance = credit given - payments received (positive = customer owes)."""
from decimal import Decimal

from django.db.models import Case, DecimalField, F, Max, Q, Sum, Value, When
from django.db.models.functions import Coalesce
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from common.exceptions import BusinessRuleError
from common.permissions import IsMerchant

from .models import KhataCustomer, KhataEntry

MONEY = DecimalField(max_digits=12, decimal_places=2)


def _shop(user):
    shop = user.merchant_profile.shops.first()
    if shop is None:
        raise BusinessRuleError("Add your shop first.", "no_shop")
    return shop


def _with_balance(qs):
    signed = Case(
        When(entries__kind=KhataEntry.Kind.CREDIT, then=F("entries__amount")),
        When(entries__kind=KhataEntry.Kind.PAYMENT, then=-F("entries__amount")),
        default=Value(0),
        output_field=MONEY,
    )
    return qs.annotate(balance=Coalesce(Sum(signed), Value(Decimal("0")), output_field=MONEY), last_entry_at=Max("entries__created_at"))


class CustomerSerializer(serializers.ModelSerializer):
    balance = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True, default=0)
    last_entry_at = serializers.DateTimeField(read_only=True, default=None)

    class Meta:
        model = KhataCustomer
        fields = ["id", "name", "phone", "note", "balance", "last_entry_at", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_phone(self, value):
        if value and not (len(value) == 10 and value.isdigit()):
            raise serializers.ValidationError("Enter a 10-digit mobile number.")
        return value


class EntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = KhataEntry
        fields = ["id", "kind", "amount", "note", "created_at"]
        read_only_fields = ["id", "created_at"]


class CustomerListView(APIView):
    """GET: customers with balances (?q= name/phone) and the shop's total due. POST: add a customer."""

    permission_classes = [IsMerchant]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        qs = _with_balance(KhataCustomer.objects.filter(shop=_shop(request.user)))
        q = request.query_params.get("q", "").strip()
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(phone__contains=q))
        rows = list(qs.order_by(F("last_entry_at").desc(nulls_last=True), "name"))
        total_due = sum((c.balance for c in rows if c.balance > 0), Decimal("0"))
        return Response({"total_due": total_due, "customers": CustomerSerializer(rows, many=True).data})

    @extend_schema(request=CustomerSerializer, responses={201: CustomerSerializer})
    def post(self, request):
        body = CustomerSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        customer = body.save(shop=_shop(request.user))
        return Response(CustomerSerializer(customer).data, status=status.HTTP_201_CREATED)


class CustomerDetailView(APIView):
    permission_classes = [IsMerchant]

    def _get(self, request, pk):
        return get_object_or_404(_with_balance(KhataCustomer.objects.filter(shop=_shop(request.user))), pk=pk)

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, pk):
        customer = self._get(request, pk)
        return Response({**CustomerSerializer(customer).data, "entries": EntrySerializer(customer.entries.all()[:200], many=True).data})

    @extend_schema(request=CustomerSerializer, responses=CustomerSerializer)
    def patch(self, request, pk):
        customer = self._get(request, pk)
        body = CustomerSerializer(customer, data=request.data, partial=True)
        body.is_valid(raise_exception=True)
        body.save()
        return Response(CustomerSerializer(self._get(request, pk)).data)

    def delete(self, request, pk):
        customer = self._get(request, pk)
        if customer.balance != 0:
            raise BusinessRuleError("Settle the balance before removing this customer.", "balance_due")
        customer.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class EntryCreateView(APIView):
    """POST /khata/customers/<id>/entries/ {kind, amount, note}: returns the entry and the new balance."""

    permission_classes = [IsMerchant]

    @extend_schema(request=EntrySerializer, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        customer = get_object_or_404(KhataCustomer.objects.filter(shop=_shop(request.user)), pk=pk)
        body = EntrySerializer(data=request.data)
        body.is_valid(raise_exception=True)
        entry = body.save(customer=customer, created_by=request.user)
        balance = _with_balance(KhataCustomer.objects.filter(pk=pk)).get().balance
        return Response({"entry": EntrySerializer(entry).data, "balance": balance}, status=status.HTTP_201_CREATED)
