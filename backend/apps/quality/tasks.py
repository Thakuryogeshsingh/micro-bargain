from celery import shared_task

from . import services


@shared_task
def auto_refund_unanswered():
    return services.auto_refund_unanswered()


@shared_task
def refresh_quality_scores():
    services.refresh_all_scores()
