from rest_framework.permissions import BasePermission


def _has_role(request, role):
    return bool(request.user and request.user.is_authenticated and request.user.role == role)


class IsCustomer(BasePermission):
    message = "Only customers can do this."

    def has_permission(self, request, view):
        return _has_role(request, "customer")


class IsMerchant(BasePermission):
    message = "Only merchants can do this."

    def has_permission(self, request, view):
        return _has_role(request, "merchant")


class IsShopWorker(BasePermission):
    """Shop owners and their staff (helpers / delivery)."""

    message = "Only the shop and its staff can do this."

    def has_permission(self, request, view):
        return _has_role(request, "merchant") or _has_role(request, "staff")


class IsPlatformAdmin(BasePermission):
    def has_permission(self, request, view):
        return _has_role(request, "admin")


class IsOwner(BasePermission):
    """
    Object-level check: the object must belong to the requesting user.
    Views set `owner_field` to the attribute path of the owning user,
    e.g. "shop__merchant__user" for a Deal.
    """

    def has_object_permission(self, request, view, obj):
        owner_field = getattr(view, "owner_field", "user")
        owner = obj
        for attr in owner_field.split("__"):
            owner = getattr(owner, attr, None)
            if owner is None:
                return False
        return owner == request.user
