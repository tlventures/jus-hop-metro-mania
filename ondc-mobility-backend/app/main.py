import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.responses import HTMLResponse
from redis.asyncio import Redis

from app.core.config import settings
from app.core.logging import logger
from app.db.session import init_db, AsyncSessionLocal
from app.security.middleware import BecknSecurityMiddleware
from app.workers.queue import AsyncQueueWorker
from app.beckn.orchestrator import BecknOrchestrator
from app.api.v1.ticketing import router as ticketing_router
from app.api.v1.webhooks import router as webhooks_router
from app.api.v1.payments import router as payments_router
from app.api.v1.wallet import router as wallet_router
from app.api.v1.rewards import router as rewards_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan manager for FastAPI application startup and shutdown tasks.
    """
    logger.info("Initializing ONDC Mobility BNP Backend Core...")

    # 1. Connect Redis (with automatic in-memory FakeRedis fallback for zero-dependency local testing)
    try:
        redis_client = Redis.from_url(settings.REDIS_URL, decode_responses=False)
        await redis_client.ping()
        logger.info(f"Connected to live Redis cluster at {settings.REDIS_URL}")
    except Exception as re:
        logger.warning(f"Could not connect to live Redis ({re}). Initializing in-memory FakeRedis for local testing...")
        import fakeredis.aioredis
        redis_client = fakeredis.aioredis.FakeRedis(decode_responses=False)

    app.state.redis = redis_client

    # 2. Init DB Schema if needed
    try:
        await init_db()
        logger.info("Database schema verified")
    except Exception as e:
        logger.warning(f"DB init warning (schema may already exist): {e}")

    # 3. Start Async Queue Worker Task
    queue_worker = AsyncQueueWorker(redis_client)
    app.state.queue_worker = queue_worker

    # Build queue action handler map
    async def _queue_handler(action: str, payload: dict):
        async with AsyncSessionLocal() as session:
            orchestrator = BecknOrchestrator(session, redis_client)
            await orchestrator.record_protocol_message(payload, direction="inbound", ack_status="ACK")
            if action == "on_search":
                await orchestrator.handle_on_search(payload)
            elif action == "on_select":
                await orchestrator.handle_on_select(payload)
            elif action == "on_init":
                await orchestrator.handle_on_init(payload)
            elif action == "on_confirm":
                await orchestrator.handle_on_confirm(payload)
            else:
                await orchestrator.handle_generic_callback(action, payload)

    callback_actions = [
        "on_search",
        "on_select",
        "on_init",
        "on_confirm",
        "on_status",
        "on_cancel",
        "on_update",
        "on_track",
        "on_support",
        "on_rating",
        "on_issue",
        "on_issue_status",
        "on_receiver_recon",
        "on_settle",
    ]
    handler_map = {action: (lambda payload, action=action: _queue_handler(action, payload)) for action in callback_actions}

    worker_task = asyncio.create_task(queue_worker.start_consumer(handler_map))

    yield

    # Shutdown sequence
    logger.info("Shutting down ONDC Mobility BNP Backend Core...")
    queue_worker.stop()
    worker_task.cancel()
    await redis_client.close()
    logger.info("Shutdown complete.")


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.ONDC_CORE_VERSION,
        description="ONDC:TRV11 Metro Ticketing Buyer Network Participant (BNP) Core",
        lifespan=lifespan
    )

    # Add Security Middleware for incoming Beckn webhooks
    app.add_middleware(BecknSecurityMiddleware)

    if settings.APP_ENV == "production":
        required = {
            "SIGNING_PRIVATE_KEY_B64": settings.SIGNING_PRIVATE_KEY_B64,
            "SIGNING_PUBLIC_KEY_B64": settings.SIGNING_PUBLIC_KEY_B64,
            "ENCRYPTION_PRIVATE_KEY_B64": settings.ENCRYPTION_PRIVATE_KEY_B64,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(f"Missing required ONDC production secrets: {', '.join(missing)}")

    # CORS Middleware
    allowed_origins = [
        origin.strip()
        for origin in getattr(settings, "ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    ] if hasattr(settings, "ALLOWED_ORIGINS") else []
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins or ["*"],
        allow_credentials=bool(allowed_origins),
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Include Routers
    app.include_router(ticketing_router)
    app.include_router(payments_router)
    app.include_router(wallet_router)
    app.include_router(rewards_router)
    app.include_router(webhooks_router, prefix="/protocol/v1")
    app.include_router(webhooks_router, prefix="/ondc")

    # Serve HTML Inspector & Tester Page at Root
    @app.get("/", include_in_schema=False)
    async def serve_demo_page():
        return FileResponse("demo_inspector.html", media_type="text/html")

    @app.get("/ondc-site-verification.html", include_in_schema=False)
    async def ondc_site_verification():
        content = settings.ONDC_SITE_VERIFICATION_CONTENT or (
            "<html><body>ONDC site verification placeholder. "
            "Set ONDC_SITE_VERIFICATION_CONTENT from the Participant Portal request.</body></html>"
        )
        return HTMLResponse(content)

    @app.get("/health", tags=["Health"])
    async def health_check():
        return {"status": "HEALTHY", "version": settings.ONDC_CORE_VERSION, "domain": settings.ONDC_DOMAIN}

    @app.get("/ready", tags=["Health"])
    async def readiness_check(request: Request):
        # Verify Redis connectivity
        try:
            await request.app.state.redis.ping()
            return {"status": "READY", "redis": "CONNECTED"}
        except Exception as e:
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={"status": "UNREADY", "error": str(e)}
            )

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host=settings.HOST, port=settings.PORT, reload=settings.DEBUG)
