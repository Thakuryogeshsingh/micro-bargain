from decimal import Decimal

from django.contrib.gis.measure import D
from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.deals.models import Deal
from apps.deals.serializers import DealSerializer
from apps.shops.services import make_point
from common.permissions import IsCustomer, IsMerchant
from common.validators import validate_coordinates

from . import services
from .models import GroupDeal, LoyaltyAccount, PriceAlert


class AlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = PriceAlert
        fields = ["id", "query", "max_price", "latitude", "longitude", "is_active", "last_notified_at", "created_at"]
        read_only_fields = ["id", "last_notified_at", "created_at"]
        # Without this a form post that leaves out is_active would save the alert switched off.
        extra_kwargs = {"is_active": {"default": True}}

    def validate(self, attrs):
        if "latitude" in attrs:
            validate_coordinates(attrs["latitude"], attrs["longitude"])
        return attrs


class AlertListView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(responses=AlertSerializer(many=True))
    def get(self, request):
        return Response(AlertSerializer(request.user.price_alerts.all(), many=True).data)

    @extend_schema(request=AlertSerializer, responses={201: AlertSerializer})
    def post(self, request):
        if request.user.price_alerts.filter(is_active=True).count() >= 20:
            return Response({"error": {"code": "too_many", "message": "You can keep up to 20 alerts."}}, status=400)
        body = AlertSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        alert = body.save(user=request.user)
        services.check_price_alerts()  # a matching deal may already be live
        return Response(AlertSerializer(alert).data, status=status.HTTP_201_CREATED)


class AlertDetailView(APIView):
    permission_classes = [IsCustomer]

    def delete(self, request, pk):
        get_object_or_404(request.user.price_alerts, pk=pk).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ShoppingListView(APIView):
    """POST {items: ["milk", "bread"], latitude, longitude}: cheapest deals per item and the best single shop."""

    permission_classes = [AllowAny]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        items = [str(i) for i in request.data.get("items", []) if str(i).strip()]
        lat, lng = Decimal(str(request.data.get("latitude"))), Decimal(str(request.data.get("longitude")))
        validate_coordinates(lat, lng)
        rows, best = services.shopping_list(items, lat, lng)
        ctx = {"request": request}
        return Response({
            "items": [{"item": r["item"], "deals": DealSerializer(r["deals"][:3], many=True, context=ctx).data} for r in rows],
            "best_shop": None if best is None else {
                "id": best["shop"].id, "name": best["shop"].name, "covers": len(best["deals"]), "of": len(rows),
                "total": sum(d.offer_price for d in best["deals"].values()),
                "deals": DealSerializer(list(best["deals"].values()), many=True, context=ctx).data,
            },
        })


def _group_json(group, user, request):
    joined = user.is_authenticated and group.members.filter(user=user).exists()
    return {
        "id": group.id, "target": group.target, "extra_percent": group.extra_percent, "members": group.members.count(),
        "unlocked": group.is_unlocked, "joined": joined,
        "deal": DealSerializer(group.deal, context={"request": request}).data,
    }


class GroupNearbyView(APIView):
    """GET ?latitude&longitude: live mohalla deals nearby."""

    permission_classes = [AllowAny]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        from apps.deals.services import live_deals

        lat, lng = request.query_params.get("latitude"), request.query_params.get("longitude")
        deals = live_deals().filter(group__isnull=False)
        if lat and lng:
            deals = deals.filter(shop__location__dwithin=(make_point(Decimal(lat), Decimal(lng)), D(m=10_000)))
        groups = GroupDeal.objects.filter(deal__in=deals).select_related("deal", "deal__shop", "deal__product")[:20]
        return Response([_group_json(g, request.user, request) for g in groups])


class GroupJoinView(APIView):
    permission_classes = [IsCustomer]

    @extend_schema(request=None, responses=OpenApiTypes.OBJECT)
    def post(self, request, pk):
        group = services.join_group(request.user, get_object_or_404(GroupDeal, pk=pk))
        return Response(_group_json(group, request.user, request))


class GroupStartView(APIView):
    """Merchants: POST {deal, target, extra_percent} to make one of their deals a mohalla deal."""

    permission_classes = [IsMerchant]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        deal = get_object_or_404(Deal.objects.filter(shop__merchant__user=request.user), pk=request.data.get("deal") or 0)
        target = int(request.data.get("target") or 5)
        extra = int(request.data.get("extra_percent") or 5)
        if not (2 <= target <= 50 and 1 <= extra <= 30):
            return Response({"error": {"code": "invalid", "message": "Target 2-50 people, extra 1-30%."}}, status=400)
        group = services.start_group(request.user, deal, target, extra)
        return Response(_group_json(group, request.user, request), status=status.HTTP_201_CREATED)


class LoyaltyView(APIView):
    """GET: points, streak and history. POST {points}: turn points into wallet money."""

    permission_classes = [IsCustomer]

    def _payload(self, user):
        account, _ = LoyaltyAccount.objects.get_or_create(user=user)
        return {
            "points": account.points, "streak_days": account.streak_days, "best_streak": account.best_streak,
            "redeem_unit": services.REDEEM_UNIT, "redeem_value": 10, "streak_target": services.STREAK_DAYS,
            "streak_bonus": services.STREAK_BONUS,
            "entries": [{"kind": e.kind, "points": e.points, "reference": e.reference, "created_at": e.created_at}
                        for e in user.loyalty_entries.all()[:30]],
        }

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        return Response(self._payload(request.user))

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        _, rupees = services.redeem(request.user, int(request.data.get("points") or 0))
        return Response({**self._payload(request.user), "credited": rupees})


class CampaignListView(APIView):
    """Live festival banners for the home screen."""

    permission_classes = [AllowAny]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        return Response([{
            "id": c.id, "title": c.title, "subtitle": c.subtitle, "color": c.color,
            "image": request.build_absolute_uri(c.image.url) if c.image else None,
            "coupon": c.coupon.code if c.coupon and c.coupon.is_active else None, "ends_at": c.ends_at,
        } for c in services.active_campaigns()])
