from django.conf import settings
from django.contrib.gis.db import models
from django.core.validators import RegexValidator

from common.models import TimeStampedModel
from common.validators import phone_validator, pincode_validator, validate_document_file, validate_image_file


class Shop(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending verification"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        SUSPENDED = "suspended", "Suspended"

    merchant = models.ForeignKey("merchants.MerchantProfile", on_delete=models.PROTECT, related_name="shops")
    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    category = models.ForeignKey("categories.Category", on_delete=models.PROTECT, related_name="shops")
    phone = models.CharField(max_length=10, blank=True, validators=[phone_validator])
    gstin = models.CharField("GSTIN", max_length=15, blank=True,
                             validators=[RegexValidator(r"^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$", "Enter a valid 15-character GSTIN")])
    cover_image = models.ImageField(upload_to="shops/covers/", blank=True, validators=[validate_image_file])

    address_line = models.CharField(max_length=255)
    landmark = models.CharField(max_length=120, blank=True)
    city = models.CharField(max_length=80, db_index=True)
    state = models.CharField(max_length=80)
    pincode = models.CharField(max_length=6, validators=[pincode_validator])
    # geography=True: distances are in metres on the earth's surface. A GiST index is created automatically.
    location = models.PointField(geography=True, srid=4326)

    opening_time = models.TimeField(null=True, blank=True)
    closing_time = models.TimeField(null=True, blank=True)
    prep_minutes = models.PositiveSmallIntegerField(default=15, help_text="Usual time to get an order ready")
    # Happy hour: before closing, every live deal gets an extra discount automatically.
    happy_hour_enabled = models.BooleanField(default=False)
    happy_hour_percent = models.PositiveSmallIntegerField(default=15)
    happy_hour_minutes = models.PositiveSmallIntegerField(default=60, help_text="Starts this long before closing time")
    offers_pickup = models.BooleanField(default=True)
    offers_delivery = models.BooleanField(default=False)
    is_temporarily_closed = models.BooleanField(default=False)

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    rejection_reason = models.TextField(blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    rating_avg = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    rating_count = models.PositiveIntegerField(default=0)
    quality_score = models.PositiveSmallIntegerField(default=100, help_text="% of last-30-day purchases without an upheld complaint")
    quality_purchases_30d = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["status", "city"])]

    def __str__(self):
        return f"{self.name}, {self.city}"

    @property
    def latitude(self):
        return self.location.y

    @property
    def longitude(self):
        return self.location.x

    @property
    def is_live(self):
        """Visible to customers and allowed to publish deals."""
        return self.status == self.Status.APPROVED and not self.is_temporarily_closed


class ShopDocument(TimeStampedModel):
    class DocType(models.TextChoices):
        SHOP_PHOTO = "shop_photo", "Shop photograph"
        ID_PROOF = "id_proof", "Owner ID proof"
        FSSAI = "fssai", "FSSAI registration/licence"
        GST = "gst", "GST certificate"
        OTHER = "other", "Other"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        VERIFIED = "verified", "Verified"
        REJECTED = "rejected", "Rejected"

    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="documents")
    doc_type = models.CharField(max_length=20, choices=DocType.choices)
    file = models.FileField(upload_to="shops/documents/", validators=[validate_document_file])
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    remarks = models.CharField(max_length=255, blank=True)

    def __str__(self):
        return f"{self.get_doc_type_display()} for {self.shop.name}"


class FavoriteShop(TimeStampedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="favorite_shops")
    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="favorited_by")

    class Meta:
        constraints = [models.UniqueConstraint(fields=["user", "shop"], name="unique_favorite_shop")]

    def __str__(self):
        return f"{self.user.phone} ♥ {self.shop.name}"
