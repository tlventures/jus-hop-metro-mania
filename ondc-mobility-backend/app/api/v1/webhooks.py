import re
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
from redis.asyncio import Redis

from app.resilience.idempotency import IdempotencyManager
from app.workers.queue import AsyncQueueWorker
from app.core.logging import logger
from app.security.ed25519 import decrypt_subscribe_challenge

router = APIRouter(tags=["ONDC Beckn Webhooks"])


def _ack_response(status_str: str = "ACK", error_code: str | None = None, error_msg: str | None = None) -> dict:
    resp = {
        "message": {
            "ack": {
                "status": status_str
            }
        }
    }
    if status_str == "NACK":
        resp["error"] = {
            "type": "CONTEXT-ERROR",
            "code": str(error_code or "400"),
            "message": str(error_msg or "Invalid Request")
        }
    return resp


def _ttl_to_timedelta(ttl: str | None) -> timedelta:
    if not ttl:
        return timedelta(seconds=30)
    match = re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", ttl)
    if not match:
        return timedelta(seconds=30)
    hours, minutes, seconds = (int(part or 0) for part in match.groups())
    return timedelta(hours=hours, minutes=minutes, seconds=seconds)


def _context_timestamp(context: dict) -> datetime | None:
    raw = context.get("timestamp")
    if not isinstance(raw, str):
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def _is_expired_callback(context: dict) -> bool:
    timestamp = _context_timestamp(context)
    if not timestamp:
        return False
    return datetime.now(timezone.utc) > timestamp + _ttl_to_timedelta(context.get("ttl"))


async def _process_webhook_ingress(request: Request, action: str) -> dict:
    """
    Common ingress processing for incoming Beckn webhooks:
    1. Parses raw JSON payload and context message_id.
    2. Runs Redis idempotency check (`SETNX idempotency:{message_id}`).
    3. Enqueues task for background execution.
    4. Returns ACK within 1000ms SLA.
    """
    try:
        payload = await request.json()
    except Exception:
        return _ack_response("NACK")

    context = payload.get("context", {})
    message_id = context.get("message_id")

    if action == "on_confirm" and _is_expired_callback(context):
        logger.warning("NACKing on_confirm callback received after context.ttl expiry")
        return _ack_response(
            "NACK",
            "20009",
            "Callback received after confirm ttl expiry",
        )

    if not message_id:
        logger.warning(f"Incoming Beckn webhook '{action}' missing context.message_id")
        return _ack_response("ACK")

    redis: Redis = request.app.state.redis
    idem_mgr = IdempotencyManager(redis)

    # 1. Idempotency Check
    is_fresh = await idem_mgr.acquire_lock(message_id)
    if not is_fresh:
        logger.info(f"Duplicate message_id '{message_id}' received for '{action}'. Fast ACK returned.")
        return _ack_response("ACK")

    # 2. Enqueue for Async Queue Worker
    queue_worker: AsyncQueueWorker = request.app.state.queue_worker
    await queue_worker.enqueue_webhook(action, payload)

    # 3. Fast ACK within SLA
    return _ack_response("ACK")


@router.post("/on_search")
async def on_search_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_search")


@router.post("/on_select")
async def on_select_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_select")


@router.post("/on_init")
async def on_init_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_init")


@router.post("/on_confirm")
async def on_confirm_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_confirm")


@router.post("/on_status")
async def on_status_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_status")


@router.post("/on_cancel")
async def on_cancel_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_cancel")


@router.post("/on_update")
async def on_update_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_update")


@router.post("/on_track")
async def on_track_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_track")


@router.post("/on_support")
async def on_support_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_support")


@router.post("/on_rating")
async def on_rating_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_rating")


@router.post("/on_issue")
async def on_issue_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_issue")


@router.post("/on_issue_status")
async def on_issue_status_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_issue_status")


@router.post("/on_receiver_recon")
async def on_receiver_recon_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_receiver_recon")


@router.post("/on_settle")
async def on_settle_webhook(request: Request):
    return await _process_webhook_ingress(request, "on_settle")


@router.post("/on_subscribe")
async def on_subscribe(request: Request):
    try:
        payload = await request.json()
    except Exception:
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content={"error": "Invalid JSON"})

    challenge = (
        payload.get("challenge")
        or payload.get("challenge_string")
        or payload.get("message", {}).get("challenge")
        or payload.get("message", {}).get("challenge_string")
    )
    if not challenge:
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content={"error": "challenge_string required"})

    try:
        return {"answer": decrypt_subscribe_challenge(challenge)}
    except Exception as exc:
        logger.error(f"/on_subscribe challenge decrypt failed: {exc}")
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"error": "Unable to decrypt challenge"},
        )
