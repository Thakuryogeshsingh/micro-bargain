from django.db import migrations


def seed(apps, schema_editor):
    CommissionRule = apps.get_model("commissions", "CommissionRule")
    if not CommissionRule.objects.filter(category=None).exists():
        CommissionRule.objects.create(category=None, rate_percent=3)  # doc example: 3%


class Migration(migrations.Migration):
    dependencies = [("commissions", "0002_initial")]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
