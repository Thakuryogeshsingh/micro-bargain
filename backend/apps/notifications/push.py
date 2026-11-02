"""Push delivery backends. send_push() returns the tokens that the provider says are no longer valid."""
import logging

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

logger = logging.getLogger(__name__)


class PushError(Exception):
    pass


def send_push(tokens, title, body, data):
    if settings.PUSH_BACKEND == "console":
        logger.info("PUSH to %s device(s): %s | %s | %s", len(tokens), title, body, data)
        return []
    if settings.PUSH_BACKEND == "fcm":
        return _send_fcm(tokens, title, body, data)
    raise ImproperlyConfigured(f"Unknown PUSH_BACKEND {settings.PUSH_BACKEND!r}")


_firebase_app = None


def _firebase():
    global _firebase_app
    if _firebase_app is None:
        import firebase_admin
        from firebase_admin import credentials

        if not settings.FCM_CREDENTIALS_FILE:
            raise ImproperlyConfigured("Set FCM_CREDENTIALS_FILE to the Firebase service-account JSON path.")
        _firebase_app = firebase_admin.initialize_app(credentials.Certificate(settings.FCM_CREDENTIALS_FILE))
    return _firebase_app


def _send_fcm(tokens, title, body, data):
    from firebase_admin import messaging

    message = messaging.MulticastMessage(
        tokens=list(tokens),
        notification=messaging.Notification(title=title, body=body),
        data={key: str(value) for key, value in data.items()},
        android=messaging.AndroidConfig(priority="high"),
    )
    response = messaging.send_each_for_multicast(message, app=_firebase())
    invalid = []
    for token, result in zip(tokens, response.responses):
        if result.success:
            continue
        if isinstance(result.exception, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
            invalid.append(token)
        else:
            logger.warning("FCM send failed: %s", result.exception)
    if response.success_count == 0 and len(invalid) < len(tokens):
        raise PushError(str(response.responses[0].exception)[:255])
    return invalid
