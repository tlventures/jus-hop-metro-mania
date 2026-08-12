from typing import Optional, Tuple
from redis.asyncio import Redis
from app.core.config import settings
from app.core.logging import logger


class IdempotencyManager:
    """
    Redis-backed Idempotency Lock Manager to ensure Beckn webhooks
    with duplicate message_ids are acknowledged immediately without duplicate processing.
    """

    def __init__(self, redis: Redis):
        self.redis = redis

    async def acquire_lock(self, message_id: str, ttl: int = settings.IDEMPOTENCY_TTL_SECONDS) -> bool:
        """
        Attempts to acquire lock for message_id.
        Returns True if fresh request (lock acquired), False if duplicate request.
        """
        key = f"idempotency:{message_id}"
        try:
            is_new = await self.redis.set(key, "PROCESSING", nx=True, ex=ttl)
            return bool(is_new)
        except Exception as e:
            logger.error(f"Redis idempotency lock error for message {message_id}: {e}")
            # In case Redis fails, fail open to avoid dropping legitimate webhooks
            return True

    async def mark_completed(self, message_id: str, ttl: int = settings.IDEMPOTENCY_TTL_SECONDS):
        """
        Updates idempotency state from PROCESSING to COMPLETED.
        """
        key = f"idempotency:{message_id}"
        try:
            await self.redis.set(key, "COMPLETED", ex=ttl)
        except Exception as e:
            logger.error(f"Redis idempotency mark completed error for {message_id}: {e}")
