from django.db import migrations

# Doc section 13.2. Prices are test prices to validate with merchants; edit them in the admin.
PLANS = [
    # code, name, price, max live deals (None = unlimited), analytics, featured, priority support
    ("free", "Free", 0, 3, "basic", False, False),
    ("basic", "Basic", 199, 15, "sales", False, True),
    ("premium", "Premium", 499, None, "advanced", True, True),
]


def seed(apps, schema_editor):
    Plan = apps.get_model("subscriptions", "Plan")
    for order, (code, name, price, max_deals, analytics, featured, priority) in enumerate(PLANS):
        Plan.objects.update_or_create(code=code, defaults={
            "name": name, "price_monthly": price, "max_active_deals": max_deals, "analytics": analytics,
            "featured_listing": featured, "priority_support": priority, "sort_order": order,
        })


class Migration(migrations.Migration):
    dependencies = [("subscriptions", "0001_initial")]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
