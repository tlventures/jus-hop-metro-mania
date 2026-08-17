import uuid
from typing import AsyncGenerator
from fastapi import Request, Depends, HTTPException, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from redis.asyncio import Redis

from app.db.session import get_db, AsyncSessionLocal
from app.db.models import User
from sqlalchemy.future import select


async def get_redis_client(request: Request) -> Redis:
    """
    Retrieves the Redis connection pool from FastAPI application state.
    """
    return request.app.state.redis


async def get_current_user(
    x_user_phone_hash: str = Header(default="demo_user_phone_hash_12345"),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Mock user authentication dependency. Resolves user from DB or auto-creates test user.
    """
    stmt = select(User).where(User.phone_number_hash == x_user_phone_hash)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        user = User(
            id=uuid.uuid4(),
            phone_number_hash=x_user_phone_hash,
            reward_points_balance=500  # Default 500 points for demo user
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)

    return user
