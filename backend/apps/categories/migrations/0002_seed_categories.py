from django.db import migrations

# Initial categories from the project document (section 5.4). Admin can edit or deactivate them later.
CATEGORIES = [
    ("Fruits", "फल", "fruits", False),
    ("Vegetables", "सब्ज़ी", "vegetables", False),
    ("Grocery", "किराना", "grocery", False),
    ("Dairy Products", "डेयरी", "dairy", False),
    ("Bakery", "बेकरी", "bakery", False),
    ("Snacks", "नमकीन-स्नैक्स", "snacks", False),
    ("Beverages", "पेय", "beverages", False),
    ("Meat and Seafood", "मीट और सीफ़ूड", "meat-seafood", True),
    ("Household Essentials", "घरेलू सामान", "household", False),
    ("Other Local Products", "अन्य लोकल सामान", "other", False),
]


def seed(apps, schema_editor):
    Category = apps.get_model("categories", "Category")
    for order, (name, name_hi, slug, compliance) in enumerate(CATEGORIES, start=1):
        Category.objects.update_or_create(
            slug=slug,
            defaults={"name": name, "name_hi": name_hi, "sort_order": order, "requires_compliance": compliance},
        )


def unseed(apps, schema_editor):
    Category = apps.get_model("categories", "Category")
    Category.objects.filter(slug__in=[c[2] for c in CATEGORIES]).delete()


class Migration(migrations.Migration):
    dependencies = [("categories", "0001_initial")]

    operations = [migrations.RunPython(seed, unseed)]
