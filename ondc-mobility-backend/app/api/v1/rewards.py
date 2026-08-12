"""Rewards earn surfaces — unified endpoint + streak + referral.

All non-ticket earn paths land here. The endpoint is source-agnostic; each
source has its own daily cap + point value, enforced server-side so the client
can't lie about the amount. Idempotent via `event_id`.
"""

from __future__ import annotations

import secrets
import uuid
from datetime import date, datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func

from app.api.deps import get_current_user, get_db
from app.core.logging import logger
from app.db.models import (
    LedgerEntryType,
    PointsLedger,
    ReferralLink,
    ReferralRedemption,
    StreakRecord,
    User,
)

router = APIRouter(prefix="/api/v1/rewards", tags=["Rewards — Earn"])


# ── Point economy ───────────────────────────────────────────────────────────
# Server-authoritative amounts + daily caps. Client cannot alter these.

class SourcePolicy:
    def __init__(self, points_each: int, daily_cap_events: int):
        self.points_each = points_each
        self.daily_cap_events = daily_cap_events
        @property
        def daily_cap_points(self):
            return self.points_each * self.daily_cap_events

SOURCE_POLICIES = {
    "AD_WATCH":            (10, 5),   # 10 pts × up to 5 ads/day = 50
    "ARTICLE_READ":        (10, 3),   # 10 pts × up to 3 articles/day = 30
    "QUIZ_COMPLETE":       (25, 2),   # 25 pts × up to 2 quizzes/day = 50
    "STORY_LISTEN":        (10, 2),   # 20
    "GAME_WIN":            (15, 3),   # 45
    "SURVEY_COMPLETE":     (20, 1),   # 20
    "DAILY_QUEST":         (50, 1),   # 50
    # DAILY_STREAK is dynamic — computed in the streak endpoint (5..50).
    # REFERRAL_* is one-off per referral pair.
}
TOTAL_DAILY_CAP_POINTS = 300  # ~₹30/day non-ticket
POINTS_EARNED_TTL = timedelta(days=182)


class EarnRequest(BaseModel):
    source: str = Field(min_length=1, max_length=32,
                        description="One of AD_WATCH, ARTICLE_READ, QUIZ_COMPLETE, ...")
    event_id: str = Field(min_length=1, max_length=128,
                          description="Idempotency key. Same (user, event_id) can only earn once.")
    metadata: dict = Field(default_factory=dict)


class EarnResponse(BaseModel):
    points_awarded: int
    source: str
    new_balance: int
    day_cap_remaining_source: int
    day_cap_remaining_total: int
    duplicate: bool = False


async def _day_range(dt: datetime) -> tuple[datetime, datetime]:
    day_start = datetime.combine(dt.date(), datetime.min.time(), tzinfo=timezone.utc)
    return day_start, day_start + timedelta(days=1)


async def _sum_earned_today(db: AsyncSession, user_id: uuid.UUID,
                            source: Optional[str] = None) -> int:
    start, end = await _day_range(datetime.now(timezone.utc))
    q = select(func.coalesce(func.sum(PointsLedger.points_amount), 0)).where(
        PointsLedger.user_id == user_id,
        PointsLedger.entry_type == LedgerEntryType.EARNED,
        PointsLedger.created_at >= start,
        PointsLedger.created_at < end,
    )
    if source is not None:
        q = q.where(PointsLedger.source == source)
    return int((await db.execute(q)).scalar_one())


async def _live_balance(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Balance ignoring expired points and everything burnt."""
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
    return max(0, int(earned) - int(burnt))


async def _credit_earn(
    db: AsyncSession,
    user_id: uuid.UUID,
    source: str,
    event_id: str,
    points: int,
) -> tuple[int, bool]:
    """Insert a new EARNED row with idempotency. Returns (points_credited, was_duplicate)."""
    existing = (await db.execute(
        select(PointsLedger).where(
            PointsLedger.user_id == user_id,
            PointsLedger.event_id == event_id,
        )
    )).scalar_one_or_none()
    if existing is not None:
        return (int(existing.points_amount), True)

    ledger = PointsLedger(
        id=uuid.uuid4(),
        user_id=user_id,
        transaction_id=None,
        points_amount=points,
        entry_type=LedgerEntryType.EARNED,
        source=source,
        event_id=event_id,
        expires_at=datetime.now(timezone.utc) + POINTS_EARNED_TTL,
    )
    db.add(ledger)
    user_row = (await db.execute(select(User).where(User.id == user_id).with_for_update())).scalar_one()
    user_row.reward_points_balance = int(user_row.reward_points_balance) + points
    await db.flush()
    return (points, False)


@router.post("/earn", response_model=EarnResponse)
async def earn(
    req: EarnRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    source = req.source.upper()
    policy = SOURCE_POLICIES.get(source)
    if policy is None:
        raise HTTPException(status_code=400, detail=f"Unknown reward source: {source}")

    points_each, daily_cap_events = policy
    source_cap_points = points_each * daily_cap_events

    # Enforce per-source and total daily caps BEFORE crediting.
    earned_today_source = await _sum_earned_today(db, current_user.id, source=source)
    earned_today_total = await _sum_earned_today(db, current_user.id, source=None)
    remaining_source = max(0, source_cap_points - earned_today_source)
    remaining_total = max(0, TOTAL_DAILY_CAP_POINTS - earned_today_total)
    to_credit = min(points_each, remaining_source, remaining_total)

    if to_credit <= 0:
        return EarnResponse(
            points_awarded=0,
            source=source,
            new_balance=await _live_balance(db, current_user.id),
            day_cap_remaining_source=remaining_source,
            day_cap_remaining_total=remaining_total,
            duplicate=False,
        )

    credited, dup = await _credit_earn(db, current_user.id, source, req.event_id, to_credit)
    await db.commit()

    return EarnResponse(
        points_awarded=(0 if dup else credited),
        source=source,
        new_balance=await _live_balance(db, current_user.id),
        day_cap_remaining_source=max(0, remaining_source - (0 if dup else credited)),
        day_cap_remaining_total=max(0, remaining_total - (0 if dup else credited)),
        duplicate=dup,
    )


# ── Streak ────────────────────────────────────────────────────────────────

class StreakStatus(BaseModel):
    current_day: int
    longest_day: int
    can_claim: bool
    next_claim_at: Optional[str] = None
    next_reward_points: int


class StreakClaimResponse(StreakStatus):
    points_awarded: int


def _streak_points(day: int) -> int:
    """5 pts day 1 → +5/day → cap at 50."""
    return min(50, max(5, day * 5))


def _same_utc_day(a: datetime, b: datetime) -> bool:
    return a.astimezone(timezone.utc).date() == b.astimezone(timezone.utc).date()


def _yesterday(a: datetime, b: datetime) -> bool:
    ad = a.astimezone(timezone.utc).date()
    bd = b.astimezone(timezone.utc).date()
    return (ad - bd).days == 1


async def _get_or_create_streak(db: AsyncSession, user_id: uuid.UUID) -> StreakRecord:
    row = (await db.execute(select(StreakRecord).where(StreakRecord.user_id == user_id))).scalar_one_or_none()
    if row is None:
        row = StreakRecord(user_id=user_id, current_day=0, longest_day=0)
        db.add(row)
        await db.flush()
    return row


@router.get("/streak", response_model=StreakStatus)
async def get_streak(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    row = await _get_or_create_streak(db, current_user.id)
    now = datetime.now(timezone.utc)
    last = row.last_claimed_on
    can_claim = last is None or not _same_utc_day(last, now)
    day_if_claimed = 1 if (last is None or not _yesterday(now, last)) else row.current_day + 1
    return StreakStatus(
        current_day=row.current_day,
        longest_day=row.longest_day,
        can_claim=can_claim,
        next_claim_at=(datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)).isoformat() if not can_claim else None,
        next_reward_points=_streak_points(day_if_claimed),
    )


@router.post("/streak/claim", response_model=StreakClaimResponse)
async def claim_streak(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    row = await _get_or_create_streak(db, current_user.id)
    now = datetime.now(timezone.utc)

    if row.last_claimed_on is not None and _same_utc_day(row.last_claimed_on, now):
        # Already claimed today.
        return StreakClaimResponse(
            current_day=row.current_day,
            longest_day=row.longest_day,
            can_claim=False,
            next_claim_at=(datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)).isoformat(),
            next_reward_points=_streak_points(row.current_day + 1),
            points_awarded=0,
        )

    if row.last_claimed_on is None or not _yesterday(now, row.last_claimed_on):
        row.current_day = 1
    else:
        row.current_day += 1
    row.longest_day = max(row.longest_day, row.current_day)
    row.last_claimed_on = now
    points = _streak_points(row.current_day)

    event_id = f"streak:{current_user.id}:{now.date().isoformat()}"
    credited, _ = await _credit_earn(db, current_user.id, "DAILY_STREAK", event_id, points)
    await db.commit()

    return StreakClaimResponse(
        current_day=row.current_day,
        longest_day=row.longest_day,
        can_claim=False,
        next_claim_at=(datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)).isoformat(),
        next_reward_points=_streak_points(row.current_day + 1),
        points_awarded=credited,
    )


# ── Referral ──────────────────────────────────────────────────────────────

REFERRAL_PREFIX = "SAFAR-"
REFERRAL_POINTS_REFERRER = 100
REFERRAL_POINTS_REFERRED = 50


def _mint_referral_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return REFERRAL_PREFIX + "".join(secrets.choice(alphabet) for _ in range(6))


class ReferralCodeResponse(BaseModel):
    code: str
    share_message: str
    referrer_reward: int = REFERRAL_POINTS_REFERRER
    referred_reward: int = REFERRAL_POINTS_REFERRED


class ApplyReferralRequest(BaseModel):
    referrer_code: str = Field(min_length=6, max_length=32)


@router.get("/referral/code", response_model=ReferralCodeResponse)
async def get_referral_code(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    link = (await db.execute(select(ReferralLink).where(ReferralLink.user_id == current_user.id))).scalar_one_or_none()
    if link is None:
        code = _mint_referral_code()
        for _ in range(3):
            clash = (await db.execute(select(ReferralLink).where(ReferralLink.code == code))).scalar_one_or_none()
            if clash is None:
                break
            code = _mint_referral_code()
        link = ReferralLink(user_id=current_user.id, code=code)
        db.add(link)
        await db.commit()

    share = (f"I've been using MetroSafar for metro tickets — you get ₹5 off "
             f"your first ride if you sign up with my code: {link.code}. "
             f"Download: https://metrosafar.in")
    return ReferralCodeResponse(code=link.code, share_message=share)


@router.post("/referral/apply")
async def apply_referral(
    req: ApplyReferralRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    code = req.referrer_code.strip().upper()
    if not code.startswith(REFERRAL_PREFIX):
        raise HTTPException(status_code=400, detail="Malformed code.")

    link = (await db.execute(select(ReferralLink).where(ReferralLink.code == code))).scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=404, detail="Referrer code not found.")
    if link.user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You can't use your own code.")

    existing = (await db.execute(
        select(ReferralRedemption).where(ReferralRedemption.referred_user_id == current_user.id)
    )).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=409, detail="You've already used a referral code.")

    db.add(ReferralRedemption(
        referred_user_id=current_user.id,
        referrer_user_id=link.user_id,
        referrer_code=code,
    ))
    await db.commit()

    return {
        "applied": True,
        "referrer_code": code,
        "message": ("Referral applied. You and your referrer earn points when "
                    "you book your first metro ticket."),
    }


async def credit_referral_on_first_ticket(
    db: AsyncSession,
    user_id: uuid.UUID,
    transaction_id: uuid.UUID,
) -> None:
    """Called from /confirm — if this user was referred and hasn't been credited
    yet, award both parties. Idempotent via event_id."""
    red = (await db.execute(
        select(ReferralRedemption).where(
            ReferralRedemption.referred_user_id == user_id,
            ReferralRedemption.activated_at.is_(None),
        )
    )).scalar_one_or_none()
    if red is None:
        return

    referrer_event = f"referral:referrer:{red.referred_user_id}"
    referred_event = f"referral:referred:{red.referred_user_id}"
    try:
        await _credit_earn(db, red.referrer_user_id, "REFERRAL_REFERRER", referrer_event, REFERRAL_POINTS_REFERRER)
        await _credit_earn(db, red.referred_user_id, "REFERRAL_REFERRED", referred_event, REFERRAL_POINTS_REFERRED)
        red.activated_at = datetime.now(timezone.utc)
        await db.commit()
    except Exception as e:
        logger.error(f"Referral credit failed for user {user_id}: {e}")
        await db.rollback()
