"""Business logic for the products app."""
from django.conf import settings
from django.db.models import ProtectedError

from common.exceptions import BusinessRuleError

from .models import ProductImage


def add_image(product, image):
    if product.images.count() >= settings.MAX_IMAGES_PER_PRODUCT:
        raise BusinessRuleError(
            f"A product can have up to {settings.MAX_IMAGES_PER_PRODUCT} images.", "image_limit"
        )
    return ProductImage.objects.create(product=product, image=image, sort_order=product.images.count())


def delete_product(product):
    """Delete a product. Products already used in deals are deactivated instead, to keep order history."""
    try:
        product.delete()
        return "deleted"
    except ProtectedError:
        product.is_active = False
        product.save(update_fields=["is_active", "updated_at"])
        return "deactivated"
