"""Customer <-> shop chat. The app polls for new messages; the other side also gets a push notification."""
from django.db import transaction
from django.db.models import F, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.notifications import services as notifications
from apps.shops.models import Shop
from common.exceptions import BusinessRuleError
from common.permissions import IsCustomer

from .models import Conversation, Message


def _mine(user):
    """Conversations the user takes part in (as the customer, or as the shop's owner)."""
    return Conversation.objects.filter(Q(customer=user) | Q(shop__merchant__user=user)).select_related("shop", "customer")


def _is_shop_side(conversation, user):
    return conversation.customer_id != user.id


class MessageSerializer(serializers.ModelSerializer):
    mine = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = ["id", "text", "mine", "created_at"]

    def get_mine(self, obj) -> bool:
        return obj.sender_id == self.context["user"].id


def _conversation_json(c, user):
    shop_side = _is_shop_side(c, user)
    return {
        "id": c.id,
        "shop": c.shop_id,
        "title": (c.customer.name or c.customer.phone[:5] + "xxxxx") if shop_side else c.shop.name,
        "last_message": c.last_message,
        "last_message_at": c.last_message_at,
        "unread": c.shop_unread if shop_side else c.customer_unread,
    }


class ConversationListView(APIView):
    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        rows = [_conversation_json(c, request.user) for c in _mine(request.user) if c.last_message_at]
        return Response(rows)


class StartView(APIView):
    """Customers: POST /chat/start/ {shop} -> the conversation with that shop (created once)."""

    permission_classes = [IsCustomer]

    @extend_schema(request=OpenApiTypes.OBJECT, responses=OpenApiTypes.OBJECT)
    def post(self, request):
        shop = get_object_or_404(Shop, pk=request.data.get("shop") or 0, status=Shop.Status.APPROVED)
        conversation, _ = Conversation.objects.get_or_create(customer=request.user, shop=shop)
        return Response(_conversation_json(conversation, request.user))


class MessagesView(APIView):
    """GET ?after=<id>: new messages (marks them read). POST {text}: send."""

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request, pk):
        conversation = get_object_or_404(_mine(request.user), pk=pk)
        qs = conversation.messages.all()
        after = request.query_params.get("after")
        qs = qs.filter(id__gt=int(after)) if after and after.isdigit() else qs.order_by("-id")[:100][::-1]
        field = "shop_unread" if _is_shop_side(conversation, request.user) else "customer_unread"
        Conversation.objects.filter(pk=pk).update(**{field: 0})
        return Response({
            "conversation": _conversation_json(conversation, request.user),
            "messages": MessageSerializer(list(qs), many=True, context={"user": request.user}).data,
        })

    @extend_schema(request=OpenApiTypes.OBJECT, responses={201: MessageSerializer})
    def post(self, request, pk):
        conversation = get_object_or_404(_mine(request.user), pk=pk)
        text = (request.data.get("text") or "").strip()
        if not text:
            raise BusinessRuleError("Write a message.", "empty")
        if len(text) > 1000:
            raise BusinessRuleError("Message is too long.", "too_long")
        shop_side = _is_shop_side(conversation, request.user)
        with transaction.atomic():
            message = Message.objects.create(conversation=conversation, sender=request.user, text=text)
            Conversation.objects.filter(pk=pk).update(
                last_message=text[:200], last_message_at=timezone.now(),
                **{"customer_unread" if shop_side else "shop_unread": F("customer_unread" if shop_side else "shop_unread") + 1},
            )
        recipient = conversation.customer if shop_side else conversation.shop.merchant.user
        title = conversation.shop.name if shop_side else (request.user.name or "ग्राहक")
        notifications.notify(recipient, notifications.Kind.NEW_MESSAGE, f"💬 {title}", text[:120], data={"chat_id": str(pk)})
        return Response(MessageSerializer(message, context={"user": request.user}).data, status=status.HTTP_201_CREATED)
