"""
Base settings shared by all environments.
Environment-specific overrides live in development.py, staging.py and production.py.
"""
from datetime import timedelta
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("DJANGO_SECRET_KEY")
DEBUG = env.bool("DJANGO_DEBUG", default=False)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])

# Windows without Docker: point these at the OSGeo4W / GDAL installation.
GDAL_LIBRARY_PATH = env("GDAL_LIBRARY_PATH", default=None)
GEOS_LIBRARY_PATH = env("GEOS_LIBRARY_PATH", default=None)

DJANGO_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.gis",
]

THIRD_PARTY_APPS = [
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "django_filters",
    "corsheaders",
    "drf_spectacular",
]

LOCAL_APPS = [
    "apps.accounts",
    "apps.customers",
    "apps.merchants",
    "apps.shops",
    "apps.categories",
    "apps.products",
    "apps.inventory",
    "apps.deals",
    "apps.reservations",
    "apps.orders",
    "apps.payments",
    "apps.notifications",
    "apps.releases",
    "apps.reviews",
    "apps.quality",
    "apps.advertisements",
    "apps.subscriptions",
    "apps.commissions",
    "apps.analytics",
    "apps.support",
    "apps.audit",
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# PostgreSQL + PostGIS
DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": env("POSTGRES_DB"),
        "USER": env("POSTGRES_USER"),
        "PASSWORD": env("POSTGRES_PASSWORD"),
        "HOST": env("POSTGRES_HOST", default="localhost"),
        "PORT": env("POSTGRES_PORT", default="5432"),
        "CONN_MAX_AGE": env.int("POSTGRES_CONN_MAX_AGE", default=60),
    }
}

AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Kolkata"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_DIRS = [BASE_DIR / "static"]
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Redis
REDIS_URL = env("REDIS_URL", default="redis://localhost:6379/0")

CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL,
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}

# Django REST Framework
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    "DEFAULT_PAGINATION_CLASS": "common.pagination.StandardPagination",
    "PAGE_SIZE": 20,
    "DEFAULT_THROTTLE_CLASSES": (
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        "anon": "60/minute",
        "user": "300/minute",
        "otp": "10/hour",
        "otp_verify": "30/hour",
    },
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "EXCEPTION_HANDLER": "common.exceptions.custom_exception_handler",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env.int("JWT_ACCESS_MINUTES", default=30)),
    # Each refresh issues a new refresh token, so anyone who opens the app within this many days stays logged in.
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env.int("JWT_REFRESH_DAYS", default=180)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Local Grocery Micro-Bargain API",
    "DESCRIPTION": "Hyperlocal grocery & live bargain marketplace",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,  # file upload fields show up correctly in Swagger
    "ENUM_NAME_OVERRIDES": {
        "DealStatusEnum": "apps.deals.models.Deal.Status",
        "ReservationStatusEnum": "apps.reservations.models.DealReservation.Status",
        "ApprovalStatusEnum": "apps.shops.models.Shop.Status",
        "OrderStatusEnum": "apps.orders.models.Order.Status",
        "OrderFulfilmentEnum": "apps.orders.models.Order.Fulfilment",
        "DealFulfilmentEnum": "apps.deals.models.Deal.Fulfilment",
        "PaymentStatusEnum": "apps.payments.models.Payment.Status",
        "OrderPaymentStatusEnum": "apps.orders.models.Order.PaymentStatus",
        "SubscriptionStatusEnum": "apps.subscriptions.models.MerchantSubscription.Status",
        "AdvertisementStatusEnum": "apps.advertisements.models.Advertisement.Status",
        "ComplaintStatusEnum": "apps.support.models.Complaint.Status",
        "CommissionStatusEnum": "apps.commissions.models.Commission.Status",
        "RefundStatusEnum": "apps.payments.models.Refund.Status",
    },
}

CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])
# The app's browser preview runs on the developer's machine. Logins use bearer tokens, not cookies,
# so letting a local page call the API exposes nothing it couldn't already do with the token.
CORS_ALLOWED_ORIGIN_REGEXES = [r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"]

# OTP
OTP_LENGTH = 6
OTP_EXPIRY_SECONDS = env.int("OTP_EXPIRY_SECONDS", default=300)
OTP_MAX_ATTEMPTS = 5
OTP_MAX_PER_HOUR = 5  # per phone number
OTP_RESEND_COOLDOWN_SECONDS = 30

# "console" logs the OTP (development). A real provider (MSG91, Twilio...) is added before launch.
SMS_BACKEND = env("SMS_BACKEND", default="console")

# Location search
DEFAULT_SEARCH_RADIUS_METERS = 2000
ALLOWED_SEARCH_RADII_METERS = [1000, 2000, 5000, 10000]

# Marketplace rules
MAX_SHOPS_PER_MERCHANT = env.int("MAX_SHOPS_PER_MERCHANT", default=1)
MAX_ADDRESSES_PER_CUSTOMER = 10
MAX_IMAGES_PER_PRODUCT = 5
MAX_DEAL_DURATION_HOURS = 48  # deals are for time-sensitive stock
RESERVATION_HOLD_MINUTES = 45  # customer must pick up within this time, else stock is released
MAX_ACTIVE_RESERVATIONS_PER_CUSTOMER = 5

# Celery
CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_TIMEZONE = TIME_ZONE
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 300
CELERY_BEAT_SCHEDULE = {
    "expire-deals": {"task": "apps.deals.tasks.expire_deals", "schedule": 60.0},
    "expire-reservations": {"task": "apps.reservations.tasks.expire_reservations", "schedule": 60.0},
    "expire-orders": {"task": "apps.orders.tasks.expire_orders", "schedule": 60.0},
    "expire-subscriptions-and-ads": {"task": "apps.subscriptions.tasks.expire_paid_services", "schedule": 300.0},
    "refresh-demo-deals": {"task": "apps.shops.tasks.refresh_demo_deals", "schedule": 3600.0},
    "happy-hours": {"task": "apps.deals.tasks.run_happy_hours", "schedule": 300.0},
    "deal-ending-alerts": {"task": "apps.notifications.tasks.deal_ending_alerts", "schedule": 600.0},
    "quality-auto-refunds": {"task": "apps.quality.tasks.auto_refund_unanswered", "schedule": 1800.0},
    "quality-scores": {"task": "apps.quality.tasks.refresh_quality_scores", "schedule": 21600.0},
}

# Demo/test servers only: fill the database with sample Bharatpur shops and keep their deals live.
SEED_DEMO = env.bool("SEED_DEMO", default=False)

# Push notifications. "console" logs pushes (development); "fcm" sends through Firebase Cloud Messaging
# using the service-account JSON at FCM_CREDENTIALS_FILE.
PUSH_BACKEND = env("PUSH_BACKEND", default="console")
FCM_CREDENTIALS_FILE = env("FCM_CREDENTIALS_FILE", default="")
MAX_DEAL_ALERTS_PER_DAY = 5  # "new deal" pushes per customer per day; reservation updates are not capped
QUIET_HOURS = (22, 7)  # no deal pushes from 10 pm to 7 am (they still appear in the in-app inbox)

# Grievance contact shown on the privacy policy and terms pages.
SUPPORT_EMAIL = env("SUPPORT_EMAIL", default="support@microbargain.in")

# Orders
ORDER_PAYMENT_MINUTES = 15  # an online order not paid within this time is cancelled and its stock released
ORDER_ACCEPT_MINUTES = 30  # the shop must accept a new order within this time, else it is cancelled (and refunded)
MAX_OPEN_ORDERS_PER_CUSTOMER = 5
ALLOW_CASH_PAYMENT = True  # cash at shop for pickup, cash on delivery for delivery
DELIVERY_FEE = env.int("DELIVERY_FEE", default=20)  # rupees
FREE_DELIVERY_ABOVE = env.int("FREE_DELIVERY_ABOVE", default=300)

# Referral: when a referred customer completes their first purchase, both get a one-time coupon.
REFERRAL_REWARD_RUPEES = 50
REFERRAL_REWARD_MIN_ORDER = 150
REFERRAL_REWARD_VALID_DAYS = 30
# A reservation may pick a later pickup time; stock stays held until this long after it.
PICKUP_GRACE_MINUTES = 30
MAX_PICKUP_AHEAD_HOURS = 24

# Bargain Plus (customer membership): free delivery and an extra discount on every order.
# Quality assurance: complain within this many hours of pickup/delivery; the shop must answer within the next.
QUALITY_COMPLAINT_HOURS = 48
QUALITY_SHOP_REPLY_HOURS = 24
# A shop is "Quality Assured" at this score or above, with enough recent purchases to mean something.
QUALITY_ASSURED_SCORE = 95
QUALITY_ASSURED_MIN_PURCHASES = 5
# Home delivery only within this distance of the shop (ordering for someone in another city uses that city's shops).
DELIVERY_MAX_KM = 15

PLUS_PRICE_RUPEES = 49
PLUS_DAYS = 30
PLUS_EXTRA_PERCENT = 5
PLUS_EXTRA_CAP_RUPEES = 50

# Wallet: cashback on every completed purchase, usable on later orders.
CASHBACK_PERCENT = 2
CASHBACK_CAP_RUPEES = 25
WALLET_MAX_PERCENT_OF_ORDER = 50

# Revenue
DEFAULT_COMMISSION_PERCENT = 3  # used when no CommissionRule matches (doc: 2-5%)
AD_PRICE_PER_DAY = {"featured_deal": 49, "home_banner": 99}  # rupees
MAX_AD_DAYS = 30

# Payments. "fake" accepts any payment signed with RAZORPAY_KEY_SECRET (development/tests);
# "razorpay" calls the real Razorpay API.
PAYMENT_BACKEND = env("PAYMENT_BACKEND", default="fake")

# Third-party integrations
MSG91_AUTH_KEY = env("MSG91_AUTH_KEY", default="")
MSG91_OTP_TEMPLATE_ID = env("MSG91_OTP_TEMPLATE_ID", default="")
RAZORPAY_KEY_ID = env("RAZORPAY_KEY_ID", default="")
RAZORPAY_KEY_SECRET = env("RAZORPAY_KEY_SECRET", default="dev-razorpay-secret")
RAZORPAY_WEBHOOK_SECRET = env("RAZORPAY_WEBHOOK_SECRET", default="dev-webhook-secret")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {"format": "{asctime} {levelname} {name} {message}", "style": "{"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "verbose"},
    },
    "root": {"handlers": ["console"], "level": "INFO"},
}
