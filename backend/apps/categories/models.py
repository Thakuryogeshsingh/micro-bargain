from django.db import models

from common.models import TimeStampedModel


class Category(TimeStampedModel):
    name = models.CharField(max_length=80, unique=True)
    name_hi = models.CharField("Name (Hindi)", max_length=80, blank=True)
    slug = models.SlugField(max_length=80, unique=True)
    icon = models.ImageField(upload_to="categories/", blank=True)
    sort_order = models.PositiveSmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    requires_compliance = models.BooleanField(
        default=False, help_text="e.g. meat and seafood: extra licence checks before approval."
    )

    class Meta:
        ordering = ["sort_order", "name"]
        verbose_name_plural = "categories"

    def __str__(self):
        return self.name
