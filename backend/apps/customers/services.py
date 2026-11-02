"""Business logic for the customers app."""
from django.conf import settings
from django.db import transaction

from common.exceptions import BusinessRuleError

from .models import Address


@transaction.atomic
def save_address(serializer, user):
    """Create or update an address, keeping at most one default per user."""
    is_new = serializer.instance is None
    if is_new and user.addresses.count() >= settings.MAX_ADDRESSES_PER_CUSTOMER:
        raise BusinessRuleError(
            f"You can save up to {settings.MAX_ADDRESSES_PER_CUSTOMER} addresses.", "address_limit"
        )
    make_default = serializer.validated_data.get("is_default") or (is_new and not user.addresses.exists())
    if make_default:
        Address.objects.filter(user=user, is_default=True).update(is_default=False)
        return serializer.save(user=user, is_default=True)
    return serializer.save(user=user)
