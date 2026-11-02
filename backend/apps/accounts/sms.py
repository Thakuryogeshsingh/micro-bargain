import logging

import requests
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from rest_framework.exceptions import APIException

logger = logging.getLogger(__name__)

MSG91_FLOW_URL = "https://control.msg91.com/api/v5/flow/"


class SMSFailed(APIException):
    status_code = 503
    default_detail = "Could not send the SMS right now. Please try again in a minute."
    default_code = "sms_failed"


def send_sms(phone, message, **template_vars):
    """Send a text message. The provider is picked by settings.SMS_BACKEND.

    Indian SMS must use a DLT-registered template, so providers send template_vars
    (e.g. otp="123456") instead of free text. `message` is what the console backend prints.
    """
    backend = settings.SMS_BACKEND
    if backend == "console":
        logger.warning("SMS to %s: %s", phone, message)
        return
    if backend == "msg91":
        return _send_msg91(phone, template_vars)
    raise ImproperlyConfigured(f"Unknown SMS_BACKEND {backend!r}")


def _send_msg91(phone, template_vars):
    if not settings.MSG91_AUTH_KEY or not settings.MSG91_OTP_TEMPLATE_ID:
        raise ImproperlyConfigured("Set MSG91_AUTH_KEY and MSG91_OTP_TEMPLATE_ID.")
    payload = {
        "template_id": settings.MSG91_OTP_TEMPLATE_ID,
        "short_url": "0",
        "recipients": [{"mobiles": f"91{phone}", **template_vars}],
    }
    try:
        response = requests.post(
            MSG91_FLOW_URL, json=payload, headers={"authkey": settings.MSG91_AUTH_KEY}, timeout=10
        )
        response.raise_for_status()
        if response.json().get("type") == "error":
            raise requests.RequestException(response.text)
    except requests.RequestException:
        logger.exception("MSG91 send to %sxxxxx failed", phone[:5])
        raise SMSFailed()
