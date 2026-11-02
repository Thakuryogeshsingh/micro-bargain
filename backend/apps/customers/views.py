from rest_framework import generics

from common.permissions import IsCustomer

from . import services
from .models import Address, CustomerProfile
from .serializers import AddressSerializer, CustomerProfileSerializer


class CustomerProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = CustomerProfileSerializer
    permission_classes = [IsCustomer]
    http_method_names = ["get", "patch"]

    def get_object(self):
        profile, _ = CustomerProfile.objects.get_or_create(user=self.request.user)
        return profile


class AddressListCreateView(generics.ListCreateAPIView):
    serializer_class = AddressSerializer
    permission_classes = [IsCustomer]
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Address.objects.none()
        return self.request.user.addresses.all()

    def perform_create(self, serializer):
        services.save_address(serializer, self.request.user)


class AddressDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = AddressSerializer
    permission_classes = [IsCustomer]
    http_method_names = ["get", "patch", "delete"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Address.objects.none()
        # Filtering by owner means other users' addresses return 404.
        return self.request.user.addresses.all()

    def perform_update(self, serializer):
        services.save_address(serializer, self.request.user)
