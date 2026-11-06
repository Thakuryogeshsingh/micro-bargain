#!/usr/bin/env sh
# Start command for Render's free plan: one container runs Django (Gunicorn) and Celery together,
# because free background workers are not available. Sized for 512 MB RAM.
set -e
python manage.py migrate --noinput
# Static files are collected in the Docker build (see Dockerfile), so nothing slow runs before the web
# server opens its port; Render fails the deploy if that takes more than a few minutes.

# Housekeeping in the background, after the server is up:
#  - admin login from DJANGO_SUPERUSER_PHONE / DJANGO_SUPERUSER_PASSWORD (created, or password updated)
#  - demo server: sample shops, photos and fresh live deals (the free plan wipes the disk on restart)
(
  sleep 5
  python manage.py ensure_admin || true
  if [ "$SEED_DEMO" = "True" ]; then
    python manage.py seed_demo || true
  fi
) &

# Worker + scheduler (deal/order expiry, pushes, refunds) in the background, one process to save memory.
celery -A config worker -B --pool solo --loglevel warning --schedule /tmp/celerybeat-schedule &

exec gunicorn config.wsgi:application --bind "0.0.0.0:${PORT:-8000}" --workers 1 --threads 4 --timeout 60 --access-logfile -
