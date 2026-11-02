from celery import shared_task

from . import services


@shared_task(autoretry_for=(ConnectionError,), retry_backoff=60, max_retries=5)
def process_refund(refund_id):
    return services.process_refund(refund_id).status
