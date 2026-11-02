"""Reports for the admin panel (doc section 14) and sales analytics for merchants.

"Sales" means completed transactions: reservations picked up at the shop plus completed orders.
Every report accepts the same filters: date_from, date_to (dates, inclusive), city, category (id).
"""
from datetime import datetime, time, timedelta
from decimal import Decimal
from io import BytesIO

from django.db.models import Avg, Count, DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce, TruncDate
from django.utils import timezone

from apps.accounts.models import User
from apps.commissions.models import Commission
from apps.deals.models import Deal
from apps.merchants.models import MerchantProfile
from apps.orders.models import Order, OrderItem
from apps.payments.models import Payment
from apps.reservations.models import DealReservation
from apps.shops.models import Shop

MONEY = DecimalField(max_digits=14, decimal_places=2)
ZERO = Decimal("0")


def _sum(qs, field):
    return qs.aggregate(total=Coalesce(Sum(field), ZERO, output_field=MONEY))["total"]


class Filters:
    def __init__(self, date_from=None, date_to=None, city=None, category=None):
        today = timezone.localdate()
        self.date_from = date_from or today - timedelta(days=29)
        self.date_to = date_to or today
        self.city = city
        self.category = category
        tz = timezone.get_current_timezone()
        self.start = datetime.combine(self.date_from, time.min, tzinfo=tz)
        self.end = datetime.combine(self.date_to + timedelta(days=1), time.min, tzinfo=tz)

    def period(self, field="created_at"):
        return Q(**{f"{field}__gte": self.start, f"{field}__lt": self.end})

    def shop(self, prefix):
        """Filter on city/category through the path to the shop (e.g. "shop__" or "")."""
        q = Q()
        if self.city:
            q &= Q(**{f"{prefix}city__iexact": self.city})
        if self.category:
            q &= Q(**{f"{prefix}category_id": self.category})
        return q


def _completed_reservations(f):
    return DealReservation.objects.filter(f.period("completed_at"), f.shop("shop__"), status=DealReservation.Status.COMPLETED)


def _completed_orders(f):
    return Order.objects.filter(f.period("completed_at"), f.shop("shop__"), status=Order.Status.COMPLETED)


# ---------- 14.1 dashboard ----------

def dashboard(f):
    deals = Deal.objects.filter(f.shop("shop__"))
    period_deals = deals.filter(f.period())
    orders = Order.objects.filter(f.period(), f.shop("shop__"))
    commissions = Commission.objects.filter(f.period(), f.shop("shop__")).exclude(status=Commission.Status.REVERSED)
    paid = Payment.objects.filter(f.period("paid_at"), status=Payment.Status.PAID)
    commission_revenue = _sum(commissions, "amount")
    subscription_revenue = _sum(paid.filter(purpose=Payment.Purpose.SUBSCRIPTION), "amount")
    ad_revenue = _sum(paid.filter(purpose=Payment.Purpose.ADVERTISEMENT), "amount")
    transaction_value = _sum(_completed_reservations(f), "total_amount") + _sum(_completed_orders(f), "subtotal")
    now = timezone.now()
    return {
        "period": {"from": f.date_from, "to": f.date_to, "city": f.city, "category": f.category},
        "total_customers": User.objects.filter(role=User.Role.CUSTOMER).count(),
        "new_customers": User.objects.filter(f.period("date_joined"), role=User.Role.CUSTOMER).count(),
        "total_merchants": MerchantProfile.objects.count(),
        "pending_merchant_approvals": MerchantProfile.objects.filter(status=MerchantProfile.Status.PENDING).count(),
        "pending_shop_approvals": Shop.objects.filter(f.shop(""), status=Shop.Status.PENDING).count(),
        "active_shops": Shop.objects.filter(f.shop(""), status=Shop.Status.APPROVED, is_temporarily_closed=False).count(),
        "active_deals": deals.filter(status=Deal.Status.ACTIVE, expires_at__gt=now).count(),
        "deals_created": period_deals.count(),
        "expired_deals": period_deals.filter(status=Deal.Status.EXPIRED).count(),
        "total_reservations": DealReservation.objects.filter(f.period(), f.shop("shop__")).count(),
        "completed_reservations": _completed_reservations(f).count(),
        "completed_orders": orders.filter(status=Order.Status.COMPLETED).count(),
        "cancelled_orders": orders.filter(status=Order.Status.CANCELLED).count(),
        "total_transaction_value": transaction_value,
        "customer_savings": _completed_reservations(f).aggregate(s=Coalesce(
            Sum((F("normal_unit_price") - F("unit_price")) * F("quantity"), output_field=MONEY), ZERO, output_field=MONEY
        ))["s"] + _sum(_completed_orders(f), "savings"),
        "commission_revenue": commission_revenue,
        "subscription_revenue": subscription_revenue,
        "advertisement_revenue": ad_revenue,
        "platform_revenue": commission_revenue + subscription_revenue + ad_revenue,
    }


# ---------- 14.2 merchant report ----------

def merchant_report(f):
    rows = []
    shops = Shop.objects.filter(f.shop("")).select_related("merchant", "category").order_by("name")
    for shop in shops:
        deals = shop.deals.filter(f.period())
        published = deals.exclude(published_at=None)
        reservations = _completed_reservations(f).filter(shop=shop)
        orders = _completed_orders(f).filter(shop=shop)
        sold_deals = published.filter(quantity_sold__gt=0).count()
        rows.append({
            "shop": shop.name, "owner": shop.merchant.owner_name, "city": shop.city, "category": shop.category.name,
            "status": shop.status, "rating": shop.rating_avg,
            "deals_published": published.count(),
            "deals_with_sales": sold_deals,
            "deal_conversion_pct": round(sold_deals * 100 / published.count(), 1) if published.count() else 0,
            "completed_reservations": reservations.count(),
            "completed_orders": orders.count(),
            "cancelled_orders": Order.objects.filter(f.period(), shop=shop, status=Order.Status.CANCELLED).count(),
            # Stock sold through deals = stock that would otherwise risk going to waste.
            "quantity_sold": published.aggregate(q=Coalesce(Sum("quantity_sold"), ZERO, output_field=MONEY))["q"],
            "quantity_expired_unsold": published.filter(status__in=Deal.FINAL_STATUSES).aggregate(
                q=Coalesce(Sum(F("quantity_total") - F("quantity_sold") - F("quantity_reserved")), ZERO, output_field=MONEY)
            )["q"],
            "revenue": _sum(reservations, "total_amount") + _sum(orders, "subtotal"),
            "commission": _sum(Commission.objects.filter(f.period(), shop=shop).exclude(status="reversed"), "amount"),
        })
    return rows


# ---------- 14.3 customer report ----------

def customer_report(f):
    reservations = _completed_reservations(f)
    orders = _completed_orders(f)
    per_customer = {}
    for row in reservations.values("customer_id").annotate(n=Count("id")):
        per_customer[row["customer_id"]] = row["n"]
    for row in orders.values("customer_id").annotate(n=Count("id")):
        per_customer[row["customer_id"]] = per_customer.get(row["customer_id"], 0) + row["n"]

    registrations = (
        User.objects.filter(f.period("date_joined"), role=User.Role.CUSTOMER)
        .annotate(day=TruncDate("date_joined")).values("day").annotate(count=Count("id")).order_by("day")
    )
    categories = {}
    for row in reservations.values("deal__product__category__name").annotate(n=Count("id")):
        categories[row["deal__product__category__name"]] = row["n"]
    for row in OrderItem.objects.filter(order__in=orders).values("deal__product__category__name").annotate(n=Count("order", distinct=True)):
        name = row["deal__product__category__name"]
        categories[name] = categories.get(name, 0) + row["n"]
    demand = {}
    for qs in (reservations, orders):
        for row in qs.values("shop__city", "shop__pincode").annotate(n=Count("id")):
            key = (row["shop__city"], row["shop__pincode"])
            demand[key] = demand.get(key, 0) + row["n"]

    active = len(per_customer)
    repeat = sum(1 for n in per_customer.values() if n >= 2)
    return {
        "active_customers": active,
        "repeat_customers": repeat,
        "repeat_rate_pct": round(repeat * 100 / active, 1) if active else 0,
        "registrations_by_day": [{"day": r["day"], "count": r["count"]} for r in registrations],
        "popular_categories": sorted(({"category": k, "purchases": v} for k, v in categories.items()), key=lambda r: -r["purchases"]),
        "demand_by_area": sorted(
            ({"city": k[0], "pincode": k[1], "purchases": v} for k, v in demand.items()), key=lambda r: -r["purchases"]
        ),
    }


# ---------- 14.4 deal report ----------

def deal_report(f, top=10):
    # Deals are filtered by the product's category, not the shop's.
    deals = Deal.objects.filter(f.period()).exclude(published_at=None)
    if f.city:
        deals = deals.filter(shop__city__iexact=f.city)
    if f.category:
        deals = deals.filter(product__category_id=f.category)
    deals = deals.select_related("shop", "product").annotate(
        reservations_count=Count("reservations", distinct=True), orders_count=Count("order_items", distinct=True)
    )

    def card(deal):
        return {"id": deal.id, "product": deal.product.name, "shop": deal.shop.name, "offer_price": deal.offer_price,
                "discount_pct": deal.discount_percent, "views": deal.view_count, "reservations": deal.reservations_count,
                "orders": deal.orders_count, "quantity_sold": deal.quantity_sold, "status": deal.status}

    total = deals.count()
    with_sales = deals.filter(quantity_sold__gt=0).count()
    return {
        "deals_published": total,
        "expired": deals.filter(status=Deal.Status.EXPIRED).count(),
        "sold_out": deals.filter(quantity_sold__gte=F("quantity_total")).count(),
        "average_discount_pct": deals.aggregate(a=Avg("discount_percent"))["a"] or 0,
        "conversion_pct": round(with_sales * 100 / total, 1) if total else 0,
        "most_viewed": [card(d) for d in deals.order_by("-view_count")[:top]],
        "most_reserved": [card(d) for d in deals.order_by("-reservations_count")[:top]],
        "most_purchased": [card(d) for d in deals.order_by("-quantity_sold")[:top]],
    }


# ---------- merchant app ----------

def merchant_sales(user, days=30):
    """Daily sales for the merchant's own shops (Basic plan and above)."""
    tz_start = timezone.localdate() - timedelta(days=days - 1)
    f = Filters(date_from=tz_start)
    shop_ids = list(Shop.objects.filter(merchant__user=user).values_list("id", flat=True))
    by_day = {}
    for qs, amount in ((_completed_reservations(f), "total_amount"), (_completed_orders(f), "subtotal")):
        for row in (qs.filter(shop_id__in=shop_ids).annotate(day=TruncDate("completed_at"))
                    .values("day").annotate(sales=Sum(amount), count=Count("id"))):
            entry = by_day.setdefault(row["day"], {"day": row["day"], "sales": ZERO, "transactions": 0})
            entry["sales"] += row["sales"]
            entry["transactions"] += row["count"]
    top_products = {}
    for row in _completed_reservations(f).filter(shop_id__in=shop_ids).values("deal__product__name").annotate(s=Sum("total_amount")):
        top_products[row["deal__product__name"]] = row["s"]
    for row in OrderItem.objects.filter(order__in=_completed_orders(f).filter(shop_id__in=shop_ids)).values("product_name").annotate(s=Sum("line_total")):
        top_products[row["product_name"]] = top_products.get(row["product_name"], ZERO) + row["s"]
    return {
        "days": days,
        "total_sales": sum((d["sales"] for d in by_day.values()), ZERO),
        "daily": sorted(by_day.values(), key=lambda d: d["day"]),
        "top_products": sorted(({"product": k, "sales": v} for k, v in top_products.items()), key=lambda r: -r["sales"])[:10],
    }


# ---------- Excel ----------

def to_excel(sheets):
    """sheets: {"Sheet name": [row dicts]} -> .xlsx bytes."""
    from openpyxl import Workbook
    from openpyxl.styles import Font

    workbook = Workbook()
    workbook.remove(workbook.active)
    for name, rows in sheets.items():
        sheet = workbook.create_sheet(name[:31])
        if not rows:
            sheet.append(["No data for these filters"])
            continue
        headers = list(rows[0].keys())
        sheet.append([h.replace("_", " ").title() for h in headers])
        for cell in sheet[1]:
            cell.font = Font(bold=True)
        for row in rows:
            sheet.append([_cell(row[h]) for h in headers])
        for column in sheet.columns:
            sheet.column_dimensions[column[0].column_letter].width = min(40, max(10, *(len(str(c.value or "")) for c in column)) + 2)
    buffer = BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


def _cell(value):
    if isinstance(value, Decimal):
        return float(value)
    return value


def report_sheets(kind, f):
    if kind == "dashboard":
        return {"Dashboard": [{"metric": k, "value": str(v)} for k, v in dashboard(f).items() if k != "period"]}
    if kind == "merchants":
        return {"Merchants": merchant_report(f)}
    if kind == "customers":
        report = customer_report(f)
        summary = [{"metric": k, "value": report[k]} for k in ("active_customers", "repeat_customers", "repeat_rate_pct")]
        return {"Summary": summary, "Registrations": report["registrations_by_day"],
                "Categories": report["popular_categories"], "Areas": report["demand_by_area"]}
    report = deal_report(f, top=50)
    summary = [{"metric": k, "value": report[k]} for k in ("deals_published", "expired", "sold_out", "average_discount_pct", "conversion_pct")]
    return {"Summary": summary, "Most viewed": report["most_viewed"], "Most reserved": report["most_reserved"],
            "Most purchased": report["most_purchased"]}
