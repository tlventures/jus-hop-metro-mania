import time
from fastapi import Request, HTTPException, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

from app.core.config import settings
from app.core.logging import logger
from app.security.ed25519 import (
    parse_authorization_header,
    compute_blake512_digest,
    verify_ed25519_signature,
    fetch_public_key_from_ondc_registry,
)


class BecknSecurityMiddleware(BaseHTTPMiddleware):
    """
    Middleware that enforces ONDC Cryptographic Webhook Security verification
    on all incoming Beckn protocol webhooks (/protocol/v1/* or /on_*).
    """

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        path = request.url.path

        # Only enforce on Beckn incoming callback routes.
        is_beckn_callback = (
            path.startswith("/protocol/v1/on_")
            or path.startswith("/ondc/on_")
            or path.startswith("/on_")
            or "webhooks" in path
        )
        if not is_beckn_callback:
            return await call_next(request)

        auth_header = request.headers.get("Authorization") or request.headers.get("authorization")

        # In dev mode or when Workbench bypass is enabled, skip signature check if no auth header
        if not auth_header:
            if settings.DEBUG or settings.APP_ENV != "production" or getattr(settings, "ALLOW_WORKBENCH_MISSING_DIGEST", False):
                logger.warning(f"Bypassing Beckn signature check for {path} (No Authorization header present)")
                return await call_next(request)
            return self._beckn_unauthorized_response("Missing Authorization header")

        try:
            params = parse_authorization_header(auth_header)
            key_id_parts = params["keyId"].split("|")
            if len(key_id_parts) < 3:
                return self._beckn_unauthorized_response("Malformed keyId in Authorization header")

            subscriber_id = key_id_parts[0]
            unique_key_id = key_id_parts[1]
            algorithm = params.get("algorithm", "ed25519")

            if algorithm.lower() != "ed25519":
                return self._beckn_unauthorized_response(f"Unsupported algorithm: {algorithm}")

            created = int(params["created"])
            expires = int(params["expires"])
            current_time = int(time.time())

            # Clock Skew & Expiry Validation
            if expires < current_time:
                return self._beckn_unauthorized_response("Authorization signature expired")

            if created > current_time + 60:
                return self._beckn_unauthorized_response("Signature created in future (clock skew)")

            # Digest Validation
            body_bytes = await request.body()
            expected_digest = compute_blake512_digest(body_bytes)
            provided_digest = (
                request.headers.get("Digest")
                or request.headers.get("digest")
                or params.get("digest", "")
            )

            if provided_digest != expected_digest:
                is_workbench_missing_digest = (
                    not provided_digest
                    and settings.ALLOW_WORKBENCH_MISSING_DIGEST
                    and subscriber_id == "workbench.ondc.tech"
                )
                if is_workbench_missing_digest:
                    logger.warning(
                        "Allowing ONDC Workbench callback without Digest header; "
                        f"using computed digest {expected_digest}"
                    )
                else:
                    logger.warning(f"Digest mismatch! Expected {expected_digest}, got {provided_digest}")
                    if not (settings.DEBUG or settings.APP_ENV != "production"):
                        return self._beckn_unauthorized_response("BLAKE-512 Body digest mismatch")

            # Signing string construction
            signing_string = f"(created): {created}\n(expires): {expires}\ndigest: {expected_digest}"

            # Public Key Resolution
            redis_client = getattr(request.app.state, "redis", None)
            public_key = await fetch_public_key_from_ondc_registry(
                subscriber_id=subscriber_id,
                unique_key_id=unique_key_id,
                redis_client=redis_client
            )

            if not public_key:
                if settings.ALLOW_WORKBENCH_MISSING_DIGEST and subscriber_id == "workbench.ondc.tech":
                    logger.warning(
                        "Allowing ONDC Workbench callback because registry public-key lookup "
                        "is unavailable for workbench.ondc.tech"
                    )
                    return await call_next(request)
                return self._beckn_unauthorized_response(f"Public key for subscriber {subscriber_id} not found")

            # Signature Verification
            is_valid = verify_ed25519_signature(
                public_key_b64=public_key,
                signature_b64=params["signature"],
                signing_string=signing_string
            )

            if not is_valid and not (settings.DEBUG or settings.APP_ENV != "production"):
                return self._beckn_unauthorized_response("Ed25519 signature verification failed")

        except Exception as e:
            logger.error(f"Beckn signature verification exception: {e}")
            if not (settings.DEBUG or settings.APP_ENV != "production"):
                return self._beckn_unauthorized_response(str(e))

        return await call_next(request)

    def _beckn_unauthorized_response(self, details: str) -> JSONResponse:
        """
        Returns ONDC Beckn compliant 401 Unauthorized Error response (Code 30001).
        """
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={
                "message": {
                    "ack": {
                        "status": "NACK"
                    }
                },
                "error": {
                    "type": "CONTEXT-ERROR",
                    "code": "30001",
                    "path": "authorization",
                    "message": f"Invalid Signature: {details}"
                }
            }
        )
