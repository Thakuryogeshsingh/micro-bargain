import logging

from celery import shared_task

from . import services

logger = logging.getLogger(__name__)


@shared_task
def expire_reservations():
    count = services.expire_reservations()
    if count:
        logger.info("Expired %s reservation(s)", count)
    return count
