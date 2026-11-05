from django.conf import settings
from django.db import models

from common.models import TimeStampedModel


class Conversation(TimeStampedModel):
    """One chat thread between a customer and a shop."""

    customer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="conversations")
    shop = models.ForeignKey("shops.Shop", on_delete=models.CASCADE, related_name="conversations")
    last_message = models.CharField(max_length=200, blank=True)
    last_message_at = models.DateTimeField(null=True, blank=True)
    customer_unread = models.PositiveIntegerField(default=0)
    shop_unread = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-last_message_at", "-id"]
        constraints = [models.UniqueConstraint(fields=["customer", "shop"], name="one_chat_per_customer_shop")]


class Message(TimeStampedModel):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    text = models.TextField(max_length=1000)

    class Meta:
        ordering = ["id"]
