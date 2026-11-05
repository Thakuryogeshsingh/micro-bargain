from django.conf import settings
from rest_framework import serializers

from common.validators import normalize_phone, phone_validator

from .models import User


class PhoneField(serializers.CharField):
    def to_internal_value(self, data):
        phone = normalize_phone(super().to_internal_value(data))
        phone_validator(phone)
        return phone


class SendOTPSerializer(serializers.Serializer):
    phone = PhoneField()


class VerifyOTPSerializer(serializers.Serializer):
    phone = PhoneField()
    code = serializers.RegexField(rf"^\d{{{settings.OTP_LENGTH}}}$", error_messages={"invalid": "Enter the 6-digit OTP."})
    referral_code = serializers.CharField(required=False, allow_blank=True, max_length=10)


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "phone", "name", "email", "role", "is_phone_verified", "date_joined"]
        read_only_fields = fields


class ProfileUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["name", "email"]


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()
