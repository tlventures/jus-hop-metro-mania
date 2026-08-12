import asyncio
import json
from typing import Dict, Any, Callable
from redis.asyncio import Redis

from app.core.logging import logger

QUEUE_KEY = "ondc:webhook:queue"
DLQ_KEY = "ondc:webhook:dlq"


class AsyncQueueWorker:
    """
    Async Message Queue Worker for non-blocking processing of incoming webhooks.
    Acknowledges incoming webhooks within 1000ms and delegates heavy DB/orchestration
    logic to background consumer tasks. Supports Dead Letter Queue (DLQ) retries.
    """

    def __init__(self, redis: Redis, max_retries: int = 3):
        self.redis = redis
        self.max_retries = max_retries
        self._running = False
        self._task = None

    async def enqueue_webhook(self, action: str, payload: Dict[str, Any]):
        """
        Pushes a webhook task onto Redis queue for background execution.
        """
        item = json.dumps({
            "action": action,
            "payload": payload,
            "retries": 0
        })
        await self.redis.rpush(QUEUE_KEY, item)
        logger.info(f"Enqueued webhook action '{action}' for async execution")

    async def start_consumer(self, handler_map: Dict[str, Callable]):
        """
        Starts the background worker loop consuming items from the queue.
        """
        self._running = True
        logger.info("Starting Async Queue Consumer worker...")

        while self._running:
            try:
                raw_item = await self.redis.blpop(QUEUE_KEY, timeout=2.0)
                if not raw_item:
                    await asyncio.sleep(0.1)
                    continue

                _, data = raw_item
                if isinstance(data, bytes):
                    data = data.decode("utf-8")

                task_data = json.loads(data)
                action = task_data.get("action")
                payload = task_data.get("payload")
                retries = task_data.get("retries", 0)

                handler = handler_map.get(action)
                if handler:
                    try:
                        await handler(payload)
                        logger.info(f"Successfully processed webhook task '{action}'")
                    except Exception as exc:
                        logger.error(f"Error processing webhook task '{action}' (attempt {retries + 1}): {exc}")
                        if retries < self.max_retries:
                            task_data["retries"] = retries + 1
                            # Re-enqueue with exponential backoff jitter
                            await asyncio.sleep(2 ** retries)
                            await self.redis.rpush(QUEUE_KEY, json.dumps(task_data))
                        else:
                            logger.error(f"Moving task '{action}' to Dead Letter Queue (DLQ)")
                            await self.redis.rpush(DLQ_KEY, json.dumps(task_data))
                else:
                    logger.warning(f"No handler registered for action '{action}'")

            except asyncio.CancelledError:
                logger.info("Async Queue Consumer worker cancelled")
                break
            except Exception as e:
                logger.error(f"Unexpected error in Async Queue Consumer: {e}")
                await asyncio.sleep(1.0)

    def stop(self):
        self._running = False
