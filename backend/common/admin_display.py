"""Shared admin list columns: coloured status badges and photo thumbnails (django-unfold)."""
from unfold.decorators import display

# Status value -> badge colour. Values are shared across apps (orders, shops, deals, payments...).
TONES = {
    "success": ["approved", "active", "completed", "paid", "processed", "delivered", "resolved", "settled", "sent", "live"],
    "info": ["confirmed", "ready", "out_for_delivery", "scheduled", "in_progress", "sold_out", "closed", "refunded"],
    "warning": ["pending", "pending_payment", "open", "paused", "disputed", "created", "draft", "unpaid", "partially_refunded", "skipped"],
    "danger": ["rejected", "cancelled", "expired", "failed", "suspended"],
}
LABELS = {value: tone for tone, values in TONES.items() for value in values}


def status_badge(field="status", description="Status"):
    """A list column showing the field's choice text in a coloured pill."""

    @display(description=description, ordering=field, label=LABELS)
    def column(self, obj):
        value = getattr(obj, field)
        text = getattr(obj, f"get_{field}_display", lambda: value)()
        return value, text

    return column


def thumbnail(get_url, description="Photo"):
    """A small photo column; get_url(obj) returns an ImageField file or None."""

    @display(description=description, image=True)
    def column(self, obj):
        image = get_url(obj)
        try:
            return image.url if image else None
        except ValueError:  # no file attached
            return None

    return column
