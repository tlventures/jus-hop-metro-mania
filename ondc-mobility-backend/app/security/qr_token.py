"""Ed25519-signed QR ticket tokens.

The token is a compact `payload.signature` string, both base64url-encoded:

    payload = {
        iss: settings.QR_TOKEN_ISSUER,
        tid: <ticket_id>,
        oid: <order_id>,
        txn: <transaction_id>,
        uid: <user_id>,
        exp: <unix epoch seconds>,
        v:   1
    }

Verification only requires the public key — the turnstile scanner can be given
the ONDC-registered public key and validate offline. The token intentionally
contains no PII beyond identifiers already needed for scanning.
"""

from __future__ import annotations

import base64
import json
import time
from typing import Any, Dict

from nacl.signing import SigningKey

from app.core.config import settings


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _signing_key() -> SigningKey:
    raw = base64.b64decode(settings.SIGNING_PRIVATE_KEY_B64)
    if len(raw) < 32:
        raise ValueError("Configured Ed25519 signing key is too short")
    return SigningKey(raw[:32])


def issue_qr_token(
    *,
    ticket_id: str,
    order_id: str,
    transaction_id: str,
    user_id: str,
    ttl_seconds: int | None = None,
) -> tuple[str, int]:
    """Return (token_string, expiry_epoch_seconds)."""
    ttl = ttl_seconds or settings.QR_TOKEN_TTL_HOURS * 3600
    exp = int(time.time()) + ttl
    claims: Dict[str, Any] = {
        "iss": settings.QR_TOKEN_ISSUER,
        "tid": ticket_id,
        "oid": order_id,
        "txn": transaction_id,
        "uid": user_id,
        "exp": exp,
        "v": 1,
    }
    payload_bytes = json.dumps(claims, separators=(",", ":"), sort_keys=True).encode()
    signature = _signing_key().sign(payload_bytes).signature
    token = f"{_b64url(payload_bytes)}.{_b64url(signature)}"
    return token, exp
