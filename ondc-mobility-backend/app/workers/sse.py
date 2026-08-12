import asyncio
import json
from typing import AsyncGenerator
from redis.asyncio import Redis
from fastapi import Request
from sse_starlette.sse import EventSourceResponse

from app.core.logging import logger


class SSEManager:
    """
    High-concurrency Redis PubSub -> Server-Sent Events (SSE) router.
    Pushes real-time Beckn callback state changes (/on_search, /on_select, /on_init, /on_confirm)
    directly to connected client devices.
    """

    def __init__(self, redis: Redis):
        self.redis = redis

    async def publish_event(self, transaction_id: str, action: str, payload: dict):
        """
        Publishes a Beckn update event to the Redis channel for the given transaction_id.
        """
        channel = f"ondc:events:{transaction_id}"
        message = json.dumps({
            "action": action,
            "transaction_id": transaction_id,
            "data": payload
        })
        try:
            await self.redis.publish(channel, message)
            logger.info(f"Published SSE event '{action}' to channel {channel}")
        except Exception as e:
            logger.error(f"Failed to publish SSE event to channel {channel}: {e}")

    async def event_generator(self, transaction_id: str, request: Request) -> AsyncGenerator[str, None]:
        """
        Subscribes to Redis PubSub channel and yields SSE events to client until connection closes.
        """
        pubsub = self.redis.pubsub()
        channel = f"ondc:events:{transaction_id}"
        await pubsub.subscribe(channel)
        logger.info(f"Client connected to SSE stream for transaction_id: {transaction_id}")

        try:
            while True:
                # Check for client disconnect
                if await request.is_disconnected():
                    logger.info(f"Client disconnected from SSE stream {transaction_id}")
                    break

                message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
                if message and message["type"] == "message":
                    data = message["data"]
                    if isinstance(data, bytes):
                        data = data.decode("utf-8")
                    yield f"data: {data}\n\n"

                await asyncio.sleep(0.1)
        except asyncio.CancelledError:
            logger.info(f"SSE stream for {transaction_id} cancelled")
        finally:
            await pubsub.unsubscribe(channel)
            await pubsub.close()
