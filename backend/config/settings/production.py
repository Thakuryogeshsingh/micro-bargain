import sentry_sdk

from .base import *  # noqa: F401,F403
from .base import env

DEBUG = False

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 60 * 60 * 24 * 365
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_CONTENT_TYPE_NOSNIFF = True
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

SENTRY_DSN = env("SENTRY_DSN", default="")
if SENTRY_DSN:
    sentry_sdk.init(dsn=SENTRY_DSN, traces_sample_rate=0.1, send_default_pii=False)

# Refuse to start with development stand-ins for money, OTP or push, unless this is an explicitly
# marked test server (ALLOW_TEST_BACKENDS=True): used before MSG91 / Razorpay / Firebase are approved.
# On such a server OTPs appear in `docker compose logs web` and payments are fake.
import logging  # noqa: E402

from django.core.exceptions import ImproperlyConfigured  # noqa: E402

from .base import PAYMENT_BACKEND, PUSH_BACKEND, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET, SMS_BACKEND  # noqa: E402

ALLOW_TEST_BACKENDS = env.bool("ALLOW_TEST_BACKENDS", default=False)
if ALLOW_TEST_BACKENDS:
    logging.getLogger(__name__).warning("TEST SERVER: console SMS / fake payments may be enabled. Not for real customers.")
else:
    secrets_missing = any(not value or value.startswith("dev-") for value in (RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET))
    if PAYMENT_BACKEND != "razorpay" or secrets_missing:
        raise ImproperlyConfigured("Production needs PAYMENT_BACKEND=razorpay and real Razorpay secrets.")
    if SMS_BACKEND == "console" or PUSH_BACKEND == "console":
        raise ImproperlyConfigured("Production needs a real SMS_BACKEND and PUSH_BACKEND (not console).")
