import pytest

from apps.releases.models import AppRelease

URL = "/api/v1/app/latest/"


def release(code, force=False):
    return AppRelease.objects.create(version_code=code, version_name=f"0.{code}.0", apk_url=f"https://example.com/{code}.apk",
                                     force_update=force, notes="नया")


@pytest.mark.django_db
class TestLatestRelease:
    def test_no_release(self, api_client):
        assert api_client.get(URL, {"current": 1}).data == {"update_available": False}

    def test_newer_release_offered(self, api_client):
        release(2)
        data = api_client.get(URL, {"current": 1}).data
        assert data["update_available"] and not data["force"] and data["apk_url"].endswith("2.apk")
        assert api_client.get(URL, {"current": 2}).data["update_available"] is False

    def test_force_cannot_be_skipped(self, api_client):
        release(2, force=True)
        release(3)
        data = api_client.get(URL, {"current": 1}).data
        assert data["force"] and data["version_code"] == 3
        assert api_client.get(URL, {"current": 2}).data["force"] is False
