from decimal import ROUND_HALF_UP, Decimal


def discount_percentage(normal_price, offer_price):
    """Discount % rounded to 2 places, e.g. (100, 60) -> Decimal("40.00")."""
    normal_price = Decimal(normal_price)
    offer_price = Decimal(offer_price)
    if normal_price <= 0:
        return Decimal("0.00")
    pct = (normal_price - offer_price) / normal_price * 100
    return pct.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
