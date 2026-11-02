from .production import *  # noqa: F401,F403

# Staging mirrors production; relax only what is needed for testing.
SECURE_HSTS_SECONDS = 0
