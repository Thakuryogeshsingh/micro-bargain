"""Shop owners add helpers and delivery staff by phone; staff log in with OTP like everyone else."""
from django.db import transaction
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import User
from apps.notifications import services as notifications
from common.exceptions import BusinessRuleError
from common.permissions import IsMerchant
from common.validators import normalize_phone

from .models import ShopStaff, staff_job


def _json(s):
    return {"id": s.id, "name": s.user.name, "phone": s.user.phone, "kind": s.kind, "is_active": s.is_active, "created_at": s.created_at}


class AddStaffSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=13)
    name = serializers.CharField(max_length=150)
    kind = serializers.ChoiceField(choices=ShopStaff.Kind.choices, default=ShopStaff.Kind.HELPER)


class TeamView(APIView):
    """Merchants: GET their staff, POST {phone, name, kind} to add someone."""

    permission_classes = [IsMerchant]

    def _shop(self, user):
        shop = user.merchant_profile.shops.first()
        if shop is None:
            raise BusinessRuleError("Add your shop first.", "no_shop")
        return shop

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        staff = ShopStaff.objects.filter(shop=self._shop(request.user), is_active=True).select_related("user")
        return Response([_json(s) for s in staff])

    @extend_schema(request=AddStaffSerializer, responses={201: OpenApiTypes.OBJECT})
    @transaction.atomic
    def post(self, request):
        body = AddStaffSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        shop = self._shop(request.user)
        phone = normalize_phone(body.validated_data["phone"])
        user = User.objects.filter(phone=phone).first()
        if user is not None and user.role not in (User.Role.CUSTOMER, User.Role.STAFF):
            raise BusinessRuleError("This number is a shop owner or admin account.", "invalid_role")
        if user is not None and ShopStaff.objects.filter(user=user, is_active=True).exclude(shop=shop).exists():
            raise BusinessRuleError("This number already works for another shop.", "taken")
        if user is None:
            user = User.objects.create_user(phone=phone, name=body.validated_data["name"], role=User.Role.STAFF)
        else:
            user.role = User.Role.STAFF
            user.name = user.name or body.validated_data["name"]
            user.save(update_fields=["role", "name"])
        job, _ = ShopStaff.objects.update_or_create(user=user, defaults={"shop": shop, "kind": body.validated_data["kind"], "is_active": True})
        notifications.notify(user, notifications.Kind.ANNOUNCEMENT, f"{shop.name} की टीम में स्वागत 👋",
                             "ऐप खोलें और इसी नंबर से लॉगिन करें।")
        return Response(_json(job), status=status.HTTP_201_CREATED)


class TeamMemberView(APIView):
    permission_classes = [IsMerchant]

    @transaction.atomic
    def delete(self, request, pk):
        job = get_object_or_404(ShopStaff.objects.filter(shop__merchant__user=request.user), pk=pk)
        job.is_active = False
        job.save(update_fields=["is_active", "updated_at"])
        job.user.role = User.Role.CUSTOMER  # back to a normal customer account
        job.user.save(update_fields=["role"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class MyJobView(APIView):
    """Staff: which shop and what role they have."""

    permission_classes = [IsAuthenticated]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        job = staff_job(request.user)
        if job is None:
            return Response({"job": None})
        return Response({"job": {"shop_id": job.shop_id, "shop_name": job.shop.name, "shop_phone": job.shop.phone, "kind": job.kind}})
