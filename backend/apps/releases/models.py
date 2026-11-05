from django.db import models

from common.models import TimeStampedModel


class AppRelease(TimeStampedModel):
    """A version of the mobile app. The app compares its own build number with the newest active
    release and offers the update, so a new APK reaches everyone without sending it around again."""

    class Platform(models.TextChoices):
        ANDROID = "android", "Android"

    platform = models.CharField(max_length=10, choices=Platform.choices, default=Platform.ANDROID)
    version_code = models.PositiveIntegerField(help_text="Build number: the part after '+' in pubspec.yaml version")
    version_name = models.CharField(max_length=20, help_text="Shown to users, e.g. 0.2.0")
    apk_url = models.URLField(help_text="Public download link of the APK (GitHub release, Google Drive, ...)")
    notes = models.TextField(blank=True, help_text="What's new, shown in the update popup")
    force_update = models.BooleanField(default=False, help_text="Older versions must update before continuing")
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-version_code"]
        constraints = [models.UniqueConstraint(fields=["platform", "version_code"], name="unique_release_per_platform")]

    def __str__(self):
        return f"{self.platform} {self.version_name} ({self.version_code})"
