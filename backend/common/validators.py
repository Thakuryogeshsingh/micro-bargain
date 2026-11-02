from django.core.exceptions import ValidationError
from django.core.validators import RegexValidator

MAX_UPLOAD_SIZE_MB = 5
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
ALLOWED_DOCUMENT_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "pdf"}

phone_validator = RegexValidator(
    regex=r"^[6-9]\d{9}$",
    message="Enter a valid 10-digit Indian mobile number.",
)

pincode_validator = RegexValidator(
    regex=r"^[1-9]\d{5}$",
    message="Enter a valid 6-digit PIN code.",
)


def validate_upload_size(file):
    if file.size > MAX_UPLOAD_SIZE_MB * 1024 * 1024:
        raise ValidationError(f"File must be smaller than {MAX_UPLOAD_SIZE_MB} MB.")


def validate_image_file(file):
    validate_upload_size(file)
    content_type = getattr(file, "content_type", None)
    if content_type and content_type not in ALLOWED_IMAGE_TYPES:
        raise ValidationError("Only JPEG, PNG and WebP images are allowed.")


def validate_document_file(file):
    validate_upload_size(file)
    ext = file.name.rsplit(".", 1)[-1].lower() if "." in file.name else ""
    if ext not in ALLOWED_DOCUMENT_EXTENSIONS:
        raise ValidationError("Only JPG, PNG, WebP or PDF files are allowed.")


def validate_coordinates(latitude, longitude):
    if not (-90 <= latitude <= 90) or not (-180 <= longitude <= 180):
        raise ValidationError("Invalid latitude/longitude.")


def normalize_phone(value):
    """Accepts '+91 98765 43210', '09876543210' etc. and returns '9876543210'."""
    digits = "".join(ch for ch in str(value) if ch.isdigit())
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    elif len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    return digits
