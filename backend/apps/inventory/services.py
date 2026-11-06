"""Business logic for inventory. Every change locks the row and writes a movement."""
from django.db import transaction

from common.exceptions import BusinessRuleError

from .models import Inventory, InventoryMovement

Reason = InventoryMovement.Reason


def _move(inventory, change, reason, user=None, reference="", note=""):
    inventory.quantity_on_hand += change
    inventory.save(update_fields=["quantity_on_hand", "updated_at"])
    return InventoryMovement.objects.create(
        inventory=inventory, change=change, balance_after=inventory.quantity_on_hand,
        reason=reason, reference=reference, note=note, created_by=user,
    )


@transaction.atomic
def adjust(user, product, change, reason, note="", low_stock_threshold=None):
    """Merchant restocks (+), records wastage (-) or corrects a count. Creates the row on first use."""
    inventory, _ = Inventory.objects.select_for_update().get_or_create(product=product, defaults={"shop": product.shop})
    if low_stock_threshold is not None:
        inventory.low_stock_threshold = low_stock_threshold
        inventory.save(update_fields=["low_stock_threshold", "updated_at"])
    if change == 0:
        return inventory
    if inventory.quantity_on_hand + change < 0:
        raise BusinessRuleError(
            f"Only {inventory.quantity_on_hand} {product.unit} in stock; cannot remove {-change}.", "insufficient_inventory"
        )
    _move(inventory, change, reason, user, note=note)
    return inventory


def check_deal_quantity(product, quantity):
    """A deal cannot offer more than the shop has (only for products whose stock is tracked)."""
    inventory = Inventory.objects.filter(product=product).first()
    if inventory is not None and quantity > inventory.quantity_on_hand:
        raise BusinessRuleError(
            f"You have only {inventory.quantity_on_hand} {product.unit} of {product.name} in stock.", "insufficient_inventory"
        )


def record_sale(product_id, quantity, reference):
    """Deduct a completed sale. Call inside the sale's transaction.

    Stock counted by hand can drift from reality, so a sale never fails here: it takes stock down to zero at most.
    """
    inventory = Inventory.objects.select_for_update().filter(product_id=product_id).first()
    if inventory is None:
        return None
    change = -min(quantity, inventory.quantity_on_hand)
    note = "" if -change == quantity else f"Sold {quantity}, but only {inventory.quantity_on_hand} was recorded"
    before = inventory.quantity_on_hand
    movement = _move(inventory, change, Reason.SALE, reference=reference, note=note)
    threshold = inventory.low_stock_threshold
    if threshold > 0 and before > threshold >= inventory.quantity_on_hand:
        from apps.notifications import services as notifications

        product = inventory.product
        notifications.notify(
            inventory.shop.merchant.user, notifications.Kind.LOW_STOCK, f"📦 {product.name} का स्टॉक कम",
            f"सिर्फ {inventory.quantity_on_hand:g} {product.unit} बचा है। जल्दी मंगवा लें।", data={"product_id": str(product.id)},
        )
    return movement
