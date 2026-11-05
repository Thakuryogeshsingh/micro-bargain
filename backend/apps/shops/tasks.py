from celery import shared_task
from django.conf import settings
from django.core.management import call_command


@shared_task
def refresh_demo_deals():
    """Keeps the demo server's deals live (they expire within hours). Only when SEED_DEMO is on."""
    if settings.SEED_DEMO:
        call_command("seed_demo")
