from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base

from app.core.config import settings
from app.core.logging import logger

Base = declarative_base()

# Configure Async SQLAlchemy Engine
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_pre_ping=True,
    # Compatibility with PgBouncer transaction mode
    connect_args={"statement_cache_size": 0, "prepared_statement_cache_size": 0} if "postgresql" in settings.DATABASE_URL else {}
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    Dependency helper that yields an async database session for FastAPI handlers.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception as e:
            await session.rollback()
            logger.error(f"Database transaction error: {e}")
            raise
        finally:
            await session.close()


async def init_db():
    """
    Initialise schema — creates new tables and applies additive column
    migrations for existing ones.

    `Base.metadata.create_all` handles new tables. Existing tables need
    explicit ALTER statements because SQLAlchemy won't touch them. All
    statements below are idempotent — they use `IF NOT EXISTS` where the
    dialect supports it.
    """
    from sqlalchemy import text

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Additive migrations. Safe to run repeatedly.
    if "postgresql" in settings.DATABASE_URL:
        migrations = [
            "ALTER TABLE points_ledger ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ",
            "ALTER TABLE points_ledger ADD COLUMN IF NOT EXISTS source VARCHAR(32)",
            "ALTER TABLE points_ledger ADD COLUMN IF NOT EXISTS event_id VARCHAR(128)",
            "CREATE INDEX IF NOT EXISTS idx_ledger_user_type_exp ON points_ledger (user_id, entry_type, expires_at)",
            "CREATE INDEX IF NOT EXISTS idx_ledger_user_source_created ON points_ledger (user_id, source, created_at)",
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_user_event ON points_ledger (user_id, event_id) WHERE event_id IS NOT NULL",
        ]
        async with engine.begin() as conn:
            for sql in migrations:
                try:
                    await conn.execute(text(sql))
                except Exception as e:  # pragma: no cover
                    logger.error(f"Migration failed [{sql}]: {e}")
