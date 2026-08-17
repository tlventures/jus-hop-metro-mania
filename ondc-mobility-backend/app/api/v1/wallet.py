"""Wallet endpoints — points balance + points→promo-code redemption.

Loyalty flow:
- Points earn: 1 pt per ₹1 fare, credited by `award_points_for_ticket` on
  ticket confirm. Each EARNED row has `expires_at = now + 6 months`.
- Points spend: user opens the Wallet, chooses how many points to burn, gets
  back a single-use promo code (10 pts → ₹1). The code has a 30-day expiry
  from mint. At /select, the user pastes the code and the discount lands on
  the txn (capped at 50% of the fare).
"""

from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func

from app.api.deps import get_current_user, get_db
from app.db.models import (
    LedgerEntryType,
    PointsLedger,
    PromoCode,
    PromoCodeStatus,
    User,
)

router = APIRouter(prefix="/api/v1/wallet", tags=["Wallet & Rewards"])

POINTS_PER_INR = 10  # 10 pts = ₹1
POINTS_EARNED_EXPIRY = timedelta(days=182)  # ~6 months
PROMO_CODE_EXPIRY = timedelta(days=30)
CODE_PREFIX = "SAFAR-"


class WalletBalance(BaseModel):
    points: int
    inr_equivalent: str
    points_per_inr: int = POINTS_PER_INR
    next_expiry_at: Optional[str] = None
    next_expiry_points: int = 0


class RedeemRequest(BaseModel):
    points_to_redeem: int = Field(ge=POINTS_PER_INR, le=100_000,
                                  description="Must be a multiple of 10 (equal to at least ₹1).")


class PromoCodeOut(BaseModel):
    code: str
    value_inr: str
    points_burnt: int
    status: str
    expires_at: str
    redeemed_at: Optional[str] = None


async def _refresh_expired_points(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Idempotent: move EARNED rows past `expires_at` into RELEASED and drop
    the user's balance. Returns points expired."""
    now = datetime.now(timezone.utc)
    stmt = select(PointsLedger).where(
        PointsLedger.user_id == user_id,
        PointsLedger.entry_type == LedgerEntryType.EARNED,
        PointsLedger.expires_at.is_not(None),
        PointsLedger.expires_at <= now,
    )
    expired = (await db.execute(stmt)).scalars().all()
    if not expired:
        return 0
    total = sum(int(row.points_amount) for row in expired)
    for row in expired:
        row.entry_type = LedgerEntryType.RELEASED
    user_row = (await db.execute(select(User).where(User.id == user_id).with_for_update())).scalar_one()
    user_row.reward_points_balance = max(0, int(user_row.reward_points_balance) - total)
    await db.flush()
    return total


async def _live_earned_balance(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Sum of unexpired EARNED points MINUS everything HELD/REDEEMED for this
    user. Falls back to `User.reward_points_balance` if the ledger is empty
    (backward-compat)."""
    now = datetime.now(timezone.utc)
    earned = (await db.execute(
        select(func.coalesce(func.sum(PointsLedger.points_amount), 0)).where(
            PointsLedger.user_id == user_id,
            PointsLedger.entry_type == LedgerEntryType.EARNED,
            (PointsLedger.expires_at.is_(None)) | (PointsLedger.expires_at > now),
        )
    )).scalar_one()
    burnt = (await db.execute(
        select(func.coalesce(func.sum(PointsLedger.points_amount), 0)).where(
            PointsLedger.user_id == user_id,
            PointsLedger.entry_type.in_([LedgerEntryType.HELD, LedgerEntryType.REDEEMED]),
        )
    )).scalar_one()
    live = max(0, int(earned) - int(burnt))
    return live


@router.get("/balance", response_model=WalletBalance)
async def get_balance(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _refresh_expired_points(db, current_user.id)
    live = await _live_earned_balance(db, current_user.id)
    await db.commit()

    # Which upcoming earn expires next, and how many points does it carry?
    next_exp_row = (await db.execute(
        select(PointsLedger.expires_at, PointsLedger.points_amount)
        .where(
            PointsLedger.user_id == current_user.id,
            PointsLedger.entry_type == LedgerEntryType.EARNED,
            PointsLedger.expires_at.is_not(None),
            PointsLedger.expires_at > datetime.now(timezone.utc),
        )
        .order_by(PointsLedger.expires_at.asc())
        .limit(1)
    )).first()

    inr = Decimal(live) / Decimal(POINTS_PER_INR)
    return WalletBalance(
        points=live,
        inr_equivalent=f"{inr:.2f}",
        points_per_inr=POINTS_PER_INR,
        next_expiry_at=next_exp_row[0].isoformat() if next_exp_row else None,
        next_expiry_points=int(next_exp_row[1]) if next_exp_row else 0,
    )


def _mint_code() -> str:
    """8-char base32-ish token, human-readable, no ambiguous chars."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I
    return CODE_PREFIX + "".join(secrets.choice(alphabet) for _ in range(8))


@router.post("/redeem", response_model=PromoCodeOut, status_code=status.HTTP_201_CREATED)
async def redeem_points(
    req: RedeemRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Convert points → single-use promo code. Non-refundable: once minted,
    the points are gone whether or not the code is later used."""
    if req.points_to_redeem % POINTS_PER_INR != 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"points_to_redeem must be a multiple of {POINTS_PER_INR}",
        )

    await _refresh_expired_points(db, current_user.id)
    live = await _live_earned_balance(db, current_user.id)
    if live < req.points_to_redeem:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient points. Live balance: {live}, requested: {req.points_to_redeem}",
        )

    value_inr = Decimal(req.points_to_redeem) / Decimal(POINTS_PER_INR)
    now = datetime.now(timezone.utc)

    # Generate a unique code (retry on collision, though extremely unlikely).
    code_str = _mint_code()
    for _ in range(3):
        existing = (await db.execute(select(PromoCode).where(PromoCode.code == code_str))).scalar_one_or_none()
        if existing is None:
            break
        code_str = _mint_code()
    else:
        raise HTTPException(status_code=500, detail="Could not mint a unique code, retry.")

    promo = PromoCode(
        id=uuid.uuid4(),
        user_id=current_user.id,
        code=code_str,
        value_inr=value_inr,
        points_burnt=req.points_to_redeem,
        status=PromoCodeStatus.ACTIVE,
        expires_at=now + PROMO_CODE_EXPIRY,
    )
    db.add(promo)

    # Burn the points immediately: a REDEEMED ledger row for these points, no
    # transaction id (this isn't a booking spend, it's a code purchase).
    db.add(PointsLedger(
        id=uuid.uuid4(),
        user_id=current_user.id,
        transaction_id=None,
        points_amount=req.points_to_redeem,
        entry_type=LedgerEntryType.REDEEMED,
    ))
    # Keep the denormalised User counter in sync so legacy readers don't drift.
    user_row = (await db.execute(select(User).where(User.id == current_user.id).with_for_update())).scalar_one()
    user_row.reward_points_balance = max(0, int(user_row.reward_points_balance) - req.points_to_redeem)

    await db.commit()
    await db.refresh(promo)

    return PromoCodeOut(
        code=promo.code,
        value_inr=f"{promo.value_inr:.2f}",
        points_burnt=int(promo.points_burnt),
        status=promo.status.value,
        expires_at=promo.expires_at.isoformat(),
    )


@router.get("/codes")
async def list_codes(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Auto-expire codes past their date on read.
    now = datetime.now(timezone.utc)
    expired = (await db.execute(
        select(PromoCode).where(
            PromoCode.user_id == current_user.id,
            PromoCode.status == PromoCodeStatus.ACTIVE,
            PromoCode.expires_at <= now,
        )
    )).scalars().all()
    for c in expired:
        c.status = PromoCodeStatus.EXPIRED
    if expired:
        await db.commit()

    rows = (await db.execute(
        select(PromoCode)
        .where(PromoCode.user_id == current_user.id)
        .order_by(PromoCode.created_at.desc())
        .limit(50)
    )).scalars().all()

    return {
        "codes": [
            {
                "code": c.code,
                "value_inr": f"{c.value_inr:.2f}",
                "points_burnt": int(c.points_burnt),
                "status": c.status.value,
                "created_at": c.created_at.isoformat(),
                "expires_at": c.expires_at.isoformat(),
                "redeemed_at": c.redeemed_at.isoformat() if c.redeemed_at else None,
            }
            for c in rows
        ]
    }
