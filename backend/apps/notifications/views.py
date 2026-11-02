from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .models import Notification
from .serializers import DeviceRegisterSerializer, DeviceTokenSerializer, NotificationSerializer


class DeviceRegisterView(APIView):
    @extend_schema(request=DeviceRegisterSerializer, responses={204: None})
    def post(self, request):
        serializer = DeviceRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.register_device(request.user, **serializer.validated_data)
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeviceUnregisterView(APIView):
    @extend_schema(request=DeviceTokenSerializer, responses={204: None})
    def post(self, request):
        serializer = DeviceTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.unregister_device(request.user, serializer.validated_data["token"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class NotificationListView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    filterset_fields = ["is_read", "kind"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Notification.objects.none()
        return self.request.user.notifications.all()


class UnreadCountView(APIView):
    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        return Response({"unread": request.user.notifications.filter(is_read=False).count()})


class MarkReadView(APIView):
    """POST /notifications/{id}/read/ for one, POST /notifications/read-all/ for everything."""

    @extend_schema(request=None, responses={200: OpenApiTypes.OBJECT})
    def post(self, request, pk=None):
        if pk is not None:
            get_object_or_404(request.user.notifications, pk=pk)
        return Response({"marked_read": services.mark_read(request.user, pk)})
