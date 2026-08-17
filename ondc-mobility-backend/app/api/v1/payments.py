"""Razorpay test-mode payment endpoints.

The client never sees the Razorpay key secret and never declares the amount:
the backend derives the amount from the txn quote created during select/init,
creates the Razorpay order server-side, and later verifies the signed payment
callback before /confirm is emitted to the BPP.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import uuid
from decimal import Decimal
from typing import Any, Dict, Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.api.deps import get_current_user, get_db, get_redis_client
from app.core.config import settings
from app.core.logging import logger
from app.db.models import Transaction, User

router = APIRouter(prefix="/api/v1/payments", tags=["Payments (Razorpay)"])


class RazorpayOrderRequest(BaseModel):
    transaction_id: str
    item_id: str = Field(default="I1")
    provider_id: str = Field(default="P1")
    passenger_count: int = Field(default=1, ge=1, le=6)


class RazorpayOrderResponse(BaseModel):
    order_id: str
    amount: int  # paise
    currency: str
    key_id: str


async def _load_owned_txn(db: AsyncSession, user_id: uuid.UUID, transaction_id: uuid.UUID) -> Transaction:
    stmt = select(Transaction).where(
        Transaction.transaction_id == transaction_id,
        Transaction.user_id == user_id,
    )
    result = await db.execute(stmt)
    txn = result.scalar_one_or_none()
    if txn is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found for this user")
    return txn


def _quote_amount(txn: Transaction) -> Decimal:
    total = (txn.total_base_fare or Decimal("0")) + (txn.tax_amount or Decimal("0"))
    if total <= 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No priced quote on file. Run /select then /init before creating a payment order.",
        )
    # Subtract any wallet discount (points or promo code) applied at /select.
    discount = txn.rewards_discount_amount or Decimal("0")
    net = total - discount
    # Razorpay refuses ₹0 orders — clamp to ₹1 minimum.
    if net < Decimal("1.00"):
        net = Decimal("1.00")
    return net


@router.post("/razorpay/order", response_model=RazorpayOrderResponse)
async def create_razorpay_order(
    req: RazorpayOrderRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    _redis: Redis = Depends(get_redis_client),
):
    """Create a Razorpay order server-side. Amount is derived from the txn quote."""
    try:
        txn_uuid = uuid.UUID(req.transaction_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    txn = await _load_owned_txn(db, current_user.id, txn_uuid)
    amount_rupees = _quote_amount(txn)
    amount_paise = int((amount_rupees * Decimal("100")).quantize(Decimal("1")))

    receipt = f"metrosafar_{req.transaction_id[:24]}"
    basic_auth = base64.b64encode(
        f"{settings.RAZORPAY_KEY_ID}:{settings.RAZORPAY_KEY_SECRET}".encode()
    ).decode()

    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            r = await client.post(
                f"{settings.RAZORPAY_API_BASE}/orders",
                headers={
                    "Authorization": f"Basic {basic_auth}",
                    "Content-Type": "application/json",
                },
                json={
                    "amount": amount_paise,
                    "currency": "INR",
                    "receipt": receipt,
                    "notes": {
                        "transaction_id": req.transaction_id,
                        "user_id": str(current_user.id),
                        "item_id": req.item_id,
                    },
                },
            )
        except httpx.HTTPError as e:
            logger.error(f"Razorpay order create failed: {e}")
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Payment provider unavailable")

    if r.status_code >= 400:
        logger.error(f"Razorpay returned {r.status_code}: {r.text[:400]}")
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Failed to create payment order")

    order = r.json()
    return RazorpayOrderResponse(
        order_id=order["id"],
        amount=int(order["amount"]),
        currency=order["currency"],
        key_id=settings.RAZORPAY_KEY_ID,
    )


def verify_razorpay_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """Constant-time HMAC-SHA256 check against `<order_id>|<payment_id>`."""
    body = f"{order_id}|{payment_id}".encode()
    expected = hmac.new(
        settings.RAZORPAY_KEY_SECRET.encode(),
        body,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
