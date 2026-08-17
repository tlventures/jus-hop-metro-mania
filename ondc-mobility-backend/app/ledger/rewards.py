import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Tuple, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from redis.asyncio import Redis

from app.db.models import User, PointsLedger, LedgerEntryType, Transaction
from app.core.logging import logger

POINTS_TO_INR_CONVERSION_RATE = 10  # e.g., 10 reward points = 1 INR
POINTS_EARNED_TTL = timedelta(days=182)  # ~6 months (matches wallet policy)


class RewardsLedgerManager:
    """
    Two-Phase Commit (2PC) Rewards Ledger Engine with Redis Redlock double-spend protection.
    """

    def __init__(self, db: AsyncSession, redis: Redis):
        self.db = db
        self.redis = redis

    async def _acquire_user_lock(self, user_id: uuid.UUID, ttl_ms: int = 5000) -> bool:
        """
        Redlock distributed lock per user to avoid concurrent double-spend attacks.
        """
        lock_key = f"lock:rewards:{user_id}"
        acquired = await self.redis.set(lock_key, "LOCKED", px=ttl_ms, nx=True)
        return bool(acquired)

    async def _release_user_lock(self, user_id: uuid.UUID):
        lock_key = f"lock:rewards:{user_id}"
        await self.redis.delete(lock_key)

    async def reserve_points(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        points_to_hold: int
    ) -> Tuple[bool, str, Decimal]:
        """
        PHASE 1 (RESERVE / HOLD):
        Deducts points from user balance and creates a 'HELD' ledger record.
        Returns (success, message, discount_amount_inr).
        """
        if points_to_hold <= 0:
            return True, "No points requested", Decimal("0.00")

        locked = await self._acquire_user_lock(user_id)
        if not locked:
            return False, "Concurrent rewards transaction in progress. Please retry.", Decimal("0.00")

        try:
            # Query user
            stmt = select(User).where(User.id == user_id).with_for_update()
            result = await self.db.execute(stmt)
            user = result.scalar_one_or_none()

            if not user:
                return False, "User not found", Decimal("0.00")

            if user.reward_points_balance < points_to_hold:
                return False, f"Insufficient points balance ({user.reward_points_balance} < {points_to_hold})", Decimal("0.00")

            # Deduct points from balance
            user.reward_points_balance -= points_to_hold

            # Create HELD ledger entry
            ledger_entry = PointsLedger(
                id=uuid.uuid4(),
                user_id=user_id,
                transaction_id=transaction_id,
                points_amount=points_to_hold,
                entry_type=LedgerEntryType.HELD
            )
            self.db.add(ledger_entry)
            await self.db.flush()

            discount_inr = Decimal(points_to_hold) / Decimal(POINTS_TO_INR_CONVERSION_RATE)
            logger.info(f"Phase 1 (Reserve): Held {points_to_hold} points (Discount: ₹{discount_inr}) for txn {transaction_id}")
            return True, "Points reserved successfully", discount_inr

        finally:
            await self._release_user_lock(user_id)

    async def commit_points(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID
    ) -> bool:
        """
        PHASE 2 (COMMIT / REDEEM):
        Transitions 'HELD' points to 'REDEEMED' when ticket is confirmed.
        """
        stmt = select(PointsLedger).where(
            PointsLedger.user_id == user_id,
            PointsLedger.transaction_id == transaction_id,
            PointsLedger.entry_type == LedgerEntryType.HELD
        )
        result = await self.db.execute(stmt)
        held_entry = result.scalar_one_or_none()

        if not held_entry:
            logger.warning(f"No HELD points found to commit for transaction {transaction_id}")
            return False

        # Create REDEEMED record
        redeemed_entry = PointsLedger(
            id=uuid.uuid4(),
            user_id=user_id,
            transaction_id=transaction_id,
            points_amount=held_entry.points_amount,
            entry_type=LedgerEntryType.REDEEMED
        )
        self.db.add(redeemed_entry)
        await self.db.flush()

        logger.info(f"Phase 2 (Commit): Committed {held_entry.points_amount} points for transaction {transaction_id}")
        return True

    async def rollback_points(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID
    ) -> bool:
        """
        ROLLBACK / RELEASE:
        Releases 'HELD' points back to user's balance on transaction failure/cancellation.
        """
        locked = await self._acquire_user_lock(user_id)
        if not locked:
            logger.warning(f"Could not acquire lock for rollback on user {user_id}")

        try:
            stmt = select(PointsLedger).where(
                PointsLedger.user_id == user_id,
                PointsLedger.transaction_id == transaction_id,
                PointsLedger.entry_type == LedgerEntryType.HELD
            )
            result = await self.db.execute(stmt)
            held_entry = result.scalar_one_or_none()

            if not held_entry:
                logger.info(f"No HELD points to release for transaction {transaction_id}")
                return False

            # Return points to user balance
            user_stmt = select(User).where(User.id == user_id).with_for_update()
            user_result = await self.db.execute(user_stmt)
            user = user_result.scalar_one_or_none()

            if user:
                user.reward_points_balance += held_entry.points_amount

            # Create RELEASED record
            released_entry = PointsLedger(
                id=uuid.uuid4(),
                user_id=user_id,
                transaction_id=transaction_id,
                points_amount=held_entry.points_amount,
                entry_type=LedgerEntryType.RELEASED
            )
            self.db.add(released_entry)
            await self.db.flush()

            logger.info(f"Rollback: Released {held_entry.points_amount} points back to user {user_id}")
            return True
        finally:
            if locked:
                await self._release_user_lock(user_id)

    async def award_points_for_ticket(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        fare_inr: Decimal,
    ) -> int:
        """
        Credit reward points to a user after a ticket confirms.

        Award = 1 point per ₹1 of fare (rounded down). Idempotent on
        (user_id, transaction_id): if an EARNED row already exists for this
        transaction the previous amount is returned unchanged.
        """
        stmt = select(PointsLedger).where(
            PointsLedger.user_id == user_id,
            PointsLedger.transaction_id == transaction_id,
            PointsLedger.entry_type == LedgerEntryType.EARNED,
        )
        existing = (await self.db.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            logger.info(f"Points already earned for txn {transaction_id}: {existing.points_amount}")
            return int(existing.points_amount)

        points = int(fare_inr) if fare_inr > 0 else 0
        if points <= 0:
            return 0

        locked = await self._acquire_user_lock(user_id)
        if not locked:
            logger.warning(f"Could not acquire lock for award on user {user_id}")

        try:
            user_stmt = select(User).where(User.id == user_id).with_for_update()
            user = (await self.db.execute(user_stmt)).scalar_one_or_none()
            if user is None:
                logger.warning(f"award_points: user {user_id} not found")
                return 0

            user.reward_points_balance += points
            self.db.add(PointsLedger(
                id=uuid.uuid4(),
                user_id=user_id,
                transaction_id=transaction_id,
                points_amount=points,
                entry_type=LedgerEntryType.EARNED,
                source="TICKET",
                event_id=f"ticket:{transaction_id}",
                expires_at=datetime.now(timezone.utc) + POINTS_EARNED_TTL,
            ))
            await self.db.flush()
            logger.info(f"Awarded {points} points to user {user_id} for txn {transaction_id}")
            return points
        finally:
            if locked:
                await self._release_user_lock(user_id)
