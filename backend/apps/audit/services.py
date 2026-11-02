"""Business logic for the audit app."""
from .models import AuditLog


def record(actor, action, obj=None, description="", **changes):
    """record(request.user, "shop.approved", shop, reason="...")"""
    return AuditLog.objects.create(
        actor=actor if getattr(actor, "is_authenticated", False) else None,
        action=action,
        object_type=obj._meta.label_lower if obj is not None else "",
        object_id=str(obj.pk) if obj is not None else "",
        description=description[:255],
        changes={key: str(value) for key, value in changes.items()},
    )
