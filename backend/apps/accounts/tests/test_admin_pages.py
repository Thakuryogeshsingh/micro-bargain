"""Every admin screen opens (list + add pages, the home dashboard and the business dashboard)."""
import pytest
from django.contrib import admin
from django.core.management import call_command
from django.urls import reverse

from apps.accounts.models import User


@pytest.fixture
def admin_client(client, db):
    user = User.objects.create_superuser(phone="9999999999", password="Admin@12345")
    user.name = "Test Admin"
    user.save()
    client.force_login(user)
    return client


@pytest.mark.django_db
def test_home_dashboard_and_reports(admin_client):
    call_command("seed_demo")
    home = admin_client.get(reverse("admin:index"))
    assert home.status_code == 200
    body = home.content.decode()
    assert "Needs attention" in body and "Latest orders" in body and "Live deals" in body
    assert admin_client.get(reverse("admin-dashboard")).status_code == 200


@pytest.mark.django_db
def test_every_model_list_and_add_page_opens(admin_client):
    call_command("seed_demo")
    failures = []
    for model, model_admin in admin.site._registry.items():
        opts = model._meta
        for name in ("changelist", "add"):
            if name == "add" and not model_admin.has_add_permission(type("R", (), {"user": User.objects.get(phone="9999999999")})()):
                continue
            url = reverse(f"admin:{opts.app_label}_{opts.model_name}_{name}")
            response = admin_client.get(url)
            if response.status_code != 200:
                failures.append((url, response.status_code))
        first = model.objects.first()
        if first is not None:
            url = reverse(f"admin:{opts.app_label}_{opts.model_name}_change", args=[first.pk])
            response = admin_client.get(url)
            if response.status_code != 200:
                failures.append((url, response.status_code))
    assert not failures, failures
