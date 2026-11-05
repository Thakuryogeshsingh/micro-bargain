"""Create the platform admin from DJANGO_SUPERUSER_PHONE / DJANGO_SUPERUSER_PASSWORD, or update its password.

Run on every server start (render_start.sh), so changing the password in the host's environment settings
and restarting is enough to reset it. Does nothing if either variable is missing.
"""
import os

from django.core.management.base import BaseCommand

from apps.accounts.models import User
from common.validators import normalize_phone


class Command(BaseCommand):
    help = "Create or update the admin login from environment variables."

    def handle(self, *args, **options):
        phone = normalize_phone(os.environ.get("DJANGO_SUPERUSER_PHONE", ""))
        password = os.environ.get("DJANGO_SUPERUSER_PASSWORD", "")
        if len(phone) != 10 or not password:
            self.stdout.write("ensure_admin: DJANGO_SUPERUSER_PHONE / DJANGO_SUPERUSER_PASSWORD not set, skipped.")
            return
        user = User.objects.filter(phone=phone).first()
        if user is None:
            User.objects.create_superuser(phone=phone, password=password, name="Admin")
            self.stdout.write(self.style.SUCCESS(f"ensure_admin: created admin {phone[:5]}xxxxx"))
            return
        changed = []
        if not (user.is_staff and user.is_superuser and user.role == User.Role.ADMIN and user.is_active):
            user.is_staff = user.is_superuser = user.is_active = True
            user.role = User.Role.ADMIN
            changed.append("permissions")
        if not user.check_password(password):
            user.set_password(password)
            changed.append("password")
        if changed:
            user.save()
        self.stdout.write(f"ensure_admin: admin {phone[:5]}xxxxx ok ({', '.join(changed) or 'no change'})")
