from celery import shared_task

from . import services


@shared_task
def check_price_alerts():
    return services.check_price_alerts()


@shared_task
def run_campaigns():
    services.run_campaigns()
