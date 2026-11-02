from celery import shared_task

from . import services


@shared_task
def expire_paid_services():
    """Close subscriptions and advertisements whose paid period is over."""
    from apps.advertisements.services import expire_ads

    return {"subscriptions": services.expire_subscriptions(), "ads": expire_ads()}
