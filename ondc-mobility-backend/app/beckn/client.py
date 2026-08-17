import json
import httpx
from typing import Dict, Any, Optional

from app.core.config import settings
from app.core.logging import logger
from app.security.ed25519 import create_beckn_headers


class BecknHttpClient:
    """
    Asynchronous Non-Blocking HTTP Client for making outbound requests
    to ONDC Gateway or BPP Metro Seller Nodes with automatic Ed25519 Beckn signatures.
    """

    def __init__(self, timeout: float = 5.0):
        self.timeout = timeout

    async def post(
        self,
        url: str,
        payload: Dict[str, Any],
        subscriber_id: Optional[str] = None,
        unique_key_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Sends an HTTP POST request with injected Beckn Authorization signature header.
        """
        raw_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")

        headers = create_beckn_headers(
            body=raw_body,
            subscriber_id=subscriber_id or settings.BAP_ID,
            unique_key_id=unique_key_id or settings.SUBSCRIBER_UNIQUE_KEY_ID,
        )

        logger.info(f"Outbound Beckn request to {url} [Action: {payload.get('context', {}).get('action')}]")

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.post(url, content=raw_body, headers=headers)
                response.raise_for_status()
                return response.json()
            except httpx.HTTPStatusError as e:
                logger.error(f"Beckn outbound request HTTP error {e.response.status_code}: {e.response.text}")
                if settings.DEBUG or settings.APP_ENV != "production":
                    logger.info(f"Dev mode fallback for HTTP status {e.response.status_code}: Returning mock ACK for {url}")
                    return {"message": {"ack": {"status": "ACK"}}}
                raise
            except Exception as e:
                logger.error(f"Beckn outbound request transport failure: {e}")
                if settings.DEBUG or settings.APP_ENV != "production":
                    logger.info(f"Dev mode fallback: Mocking ACK response for outbound {url}")
                    return {"message": {"ack": {"status": "ACK"}}}
                raise


beckn_client = BecknHttpClient()
