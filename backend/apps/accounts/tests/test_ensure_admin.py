import pytest
from django.core.management import call_command

from apps.accounts.models import User


@pytest.mark.django_db
class TestEnsureAdmin:
    def test_creates_then_updates_password(self, monkeypatch):
        monkeypatch.setenv("DJANGO_SUPERUSER_PHONE", "9876512345")
        monkeypatch.setenv("DJANGO_SUPERUSER_PASSWORD", "first-pass-1")
        call_command("ensure_admin")
        admin = User.objects.get(phone="9876512345")
        assert admin.is_superuser and admin.role == "admin" and admin.check_password("first-pass-1")

        monkeypatch.setenv("DJANGO_SUPERUSER_PASSWORD", "second-pass-2")
        call_command("ensure_admin")
        admin.refresh_from_db()
        assert admin.check_password("second-pass-2")

    def test_promotes_existing_customer_number(self, monkeypatch, make_user):
        make_user(phone="9876512346")
        monkeypatch.setenv("DJANGO_SUPERUSER_PHONE", "+91 98765 12346")
        monkeypatch.setenv("DJANGO_SUPERUSER_PASSWORD", "pass-123")
        call_command("ensure_admin")
        assert User.objects.get(phone="9876512346").is_staff

    def test_skips_without_env(self, monkeypatch):
        monkeypatch.delenv("DJANGO_SUPERUSER_PHONE", raising=False)
        call_command("ensure_admin")
        assert not User.objects.filter(is_superuser=True).exists()
