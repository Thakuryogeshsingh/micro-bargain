from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler


class BusinessRuleError(APIException):
    """Raised by services when a request is valid but breaks a business rule
    (e.g. reserving more than the available stock)."""

    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = "Request violates a business rule."
    default_code = "business_rule_violation"


def custom_exception_handler(exc, context):
    """Wrap every DRF error in one consistent shape:
    {"error": {"code": ..., "message": ..., "details": ...}}
    """
    response = exception_handler(exc, context)
    if response is None:
        return None

    details = response.data
    code = getattr(exc, "default_code", "error")
    if isinstance(details, dict) and "detail" in details:
        message = str(details["detail"])
        code = getattr(details["detail"], "code", code)
        details = None
    else:
        code = "validation_error" if response.status_code == 400 else code
        message = "Validation failed." if response.status_code == 400 else str(exc)

    response.data = {"error": {"code": code, "message": message, "details": details}}
    return response
