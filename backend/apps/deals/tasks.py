import logging

from celery import shared_task

from . import services

logger = logging.getLogger(__name__)


@shared_task
def expire_deals():
    count = services.expire_deals()
    if count:
        logger.info("Expired %s deal(s)", count)
    return count


@shared_task
def run_happy_hours():
    applied, restored = services.run_happy_hours()
    if applied or restored:
        logger.info("Happy hour: %s deal(s) discounted, %s restored", applied, restored)
    return applied, restored
