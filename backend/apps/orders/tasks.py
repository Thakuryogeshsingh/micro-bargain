import logging

from celery import shared_task

from . import services

logger = logging.getLogger(__name__)


@shared_task
def expire_orders():
    count = services.expire_orders()
    if count:
        logger.info("Cancelled %s unpaid/unanswered order(s)", count)
    return count
