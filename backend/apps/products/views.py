from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from common.permissions import IsMerchant

from . import services
from .models import Product
from .serializers import ProductImageSerializer, ProductImageUploadSerializer, ProductSerializer


class MerchantProductMixin:
    permission_classes = [IsMerchant]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Product.objects.none()
        # Scoping by owner means another merchant's product id returns 404.
        return (
            Product.objects.filter(shop__merchant__user=self.request.user)
            .select_related("category")
            .prefetch_related("images")
        )


class ProductListView(MerchantProductMixin, generics.ListAPIView):
    serializer_class = ProductSerializer
    filterset_fields = ["shop", "category", "is_active", "unit"]
    search_fields = ["name", "description"]
    ordering_fields = ["name", "standard_price", "created_at"]


class ProductCreateView(MerchantProductMixin, generics.CreateAPIView):
    serializer_class = ProductSerializer


class ProductUpdateView(MerchantProductMixin, generics.UpdateAPIView):
    serializer_class = ProductSerializer
    http_method_names = ["patch"]


class ProductDeleteView(MerchantProductMixin, generics.DestroyAPIView):
    @extend_schema(responses={204: None, 200: OpenApiTypes.OBJECT})
    def delete(self, request, *args, **kwargs):
        return super().delete(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        result = services.delete_product(self.get_object())
        if result == "deleted":
            return Response(status=status.HTTP_204_NO_CONTENT)
        return Response({"message": "Product is used in deals, so it was deactivated instead of deleted."})


class ProductImageUploadView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(request=ProductImageUploadSerializer, responses={201: ProductImageSerializer})
    def post(self, request):
        serializer = ProductImageUploadSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        product_image = services.add_image(serializer.validated_data["product"], serializer.validated_data["image"])
        return Response(ProductImageSerializer(product_image, context={"request": request}).data, status=status.HTTP_201_CREATED)
