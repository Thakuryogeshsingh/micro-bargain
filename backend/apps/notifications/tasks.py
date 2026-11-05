import logging

from celery import shared_task

from . import services

logger = logging.getLogger(__name__)


@shared_task
def send_notifications(notification_ids):
    return services.deliver(notification_ids)


@shared_task
def fan_out_new_deal(deal_id):
    count = services.notify_new_deal(deal_id)
    if count:
        logger.info("Deal %s: alerted %s customer(s)", deal_id, count)
    return count



@shared_task
def deal_ending_alerts():
    return services.deal_ending_alerts()
