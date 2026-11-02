"""Razorpay calls. With PAYMENT_BACKEND="fake" nothing leaves the server, but signatures are checked
with the same formula, so the verify/webhook code paths are identical in development and production."""
import hashlib
import hmac
import secrets

import requests
from django.conf import settings

API = "https://api.razorpay.com/v1"


class GatewayError(Exception):
    pass


def _fake():
    return settings.PAYMENT_BACKEND == "fake"


def _call(method, path, payload):
    try:
        response = requests.request(
            method, f"{API}{path}", json=payload, timeout=15,
            auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET),
        )
    except requests.RequestException as exc:
        raise GatewayError(f"Razorpay unreachable: {exc}") from exc
    if response.status_code >= 400:
        try:
            message = response.json()["error"]["description"]
        except (ValueError, KeyError):
            message = response.text[:200]
        raise GatewayError(message)
    return response.json()


def create_order(amount_paise, receipt, notes):
    if _fake():
        return {"id": f"order_fake{secrets.token_hex(8)}"}
    return _call("POST", "/orders", {"amount": amount_paise, "currency": "INR", "receipt": receipt, "notes": notes})


def refund(gateway_payment_id, amount_paise, notes):
    """Returns {"id": ..., "status": "processed" | "pending"}."""
    if _fake():
        return {"id": f"rfnd_fake{secrets.token_hex(8)}", "status": "processed"}
    return _call("POST", f"/payments/{gateway_payment_id}/refund", {"amount": amount_paise, "notes": notes})


def _sign(secret, message):
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def checkout_signature(gateway_order_id, gateway_payment_id):
    """The signature Razorpay Checkout returns to the app after a successful payment."""
    return _sign(settings.RAZORPAY_KEY_SECRET, f"{gateway_order_id}|{gateway_payment_id}".encode())


def signature_ok(gateway_order_id, gateway_payment_id, signature):
    return hmac.compare_digest(checkout_signature(gateway_order_id, gateway_payment_id), signature or "")


def webhook_signature_ok(body, signature):
    return hmac.compare_digest(_sign(settings.RAZORPAY_WEBHOOK_SECRET, body), signature or "")
