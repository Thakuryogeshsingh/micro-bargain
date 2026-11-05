from django.conf import settings
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import generics, serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from common.exceptions import BusinessRuleError

from . import services
from .serializers import (
    LogoutSerializer,
    ProfileUpdateSerializer,
    SendOTPSerializer,
    UserSerializer,
    VerifyOTPSerializer,
)


class SendOTPView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp"

    @extend_schema(
        request=SendOTPSerializer,
        responses=inline_serializer("SendOTPResponse", {
            "message": serializers.CharField(),
            "expires_in": serializers.IntegerField(),
            "test_otp": serializers.CharField(required=False, help_text="Only on test servers without real SMS"),
        }),
    )
    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        otp = services.send_otp(phone)
        body = {"message": "OTP sent.", "expires_in": settings.OTP_EXPIRY_SECONDS}
        test_otp = services.test_otp_for(phone, otp)
        if test_otp:
            body["test_otp"] = test_otp
        return Response(body)


class VerifyOTPView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "otp_verify"

    @extend_schema(
        request=VerifyOTPSerializer,
        responses=inline_serializer("LoginResponse", {
            "access": serializers.CharField(),
            "refresh": serializers.CharField(),
            "is_new_user": serializers.BooleanField(),
            "user": UserSerializer(),
        }),
    )
    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user, created = services.verify_otp(data["phone"], data["code"])
        referral_applied = False
        if created and data.get("referral_code"):
            from apps.customers.services import apply_referral

            try:
                apply_referral(user, data["referral_code"])
                referral_applied = True
            except BusinessRuleError:
                pass  # a wrong code must not block signing up
        return Response(
            {**services.issue_tokens(user), "is_new_user": created, "referral_applied": referral_applied,
             "user": UserSerializer(user).data},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class LogoutView(APIView):
    @extend_schema(request=LogoutSerializer, responses={204: None})
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.logout(serializer.validated_data["refresh"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class ProfileView(generics.RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class ProfileUpdateView(generics.UpdateAPIView):
    serializer_class = ProfileUpdateSerializer
    http_method_names = ["patch"]

    def get_object(self):
        return self.request.user

    def update(self, request, *args, **kwargs):
        super().update(request, *args, **kwargs)
        return Response(UserSerializer(request.user).data)


class DeleteAccountView(APIView):
    @extend_schema(request=None, responses={204: None})
    def post(self, request):
        services.delete_account(request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)
