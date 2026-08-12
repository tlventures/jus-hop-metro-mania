import uuid
import re
from decimal import Decimal
from typing import Optional, List, Dict, Any
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from redis.asyncio import Redis
from sse_starlette.sse import EventSourceResponse

from app.api.deps import get_db, get_redis_client, get_current_user
from app.core.config import settings
from app.db.models import (
    User,
    Transaction,
    Ticket,
    Issue,
    ReconRecord,
    PayoutRecord,
    ObservabilityEvent,
    ProtocolMessage,
    IssueStatus,
    ReconStatus,
    PayoutStatus,
)
from app.beckn.orchestrator import BecknOrchestrator
from app.workers.sse import SSEManager

router = APIRouter(prefix="/api/v1", tags=["Client Mobile Ticketing API"])


EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
PHONE_RE = re.compile(r"(?<!\d)(?:\+?\d[\d\s-]{7,}\d)(?!\d)")


def _scrub_observability_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _scrub_observability_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_scrub_observability_value(item) for item in value]
    if isinstance(value, str):
        scrubbed = EMAIL_RE.sub("[redacted-email]", value)
        scrubbed = PHONE_RE.sub("[redacted-phone]", scrubbed)
        return scrubbed
    return value


# Request / Response DTOs
class SearchRouteRequest(BaseModel):
    origin_station_id: str
    destination_station_id: str
    origin_gps: Optional[str] = None
    destination_gps: Optional[str] = None
    city_code: str = Field(default="std:040")
    gateway_url: Optional[str] = None
    transaction_id: Optional[str] = None


class SelectTicketRequest(BaseModel):
    transaction_id: str
    item_id: str
    provider_id: str = Field(default="P1")
    passenger_count: int = Field(default=1, ge=1, le=6)
    reward_points_to_redeem: int = Field(default=0, ge=0)
    promo_code: Optional[str] = Field(default=None, description="Wallet-minted promo code to apply.")


class ConfirmPaymentRequest(BaseModel):
    """Client sends only Razorpay identifiers. The backend re-verifies the
    signature and reads the true amount from the txn quote — no `amount_paid`
    field is accepted from the client."""
    transaction_id: str
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
    item_id: str = Field(default="I1")
    provider_id: str = Field(default="P1")
    passenger_count: int = Field(default=1, ge=1, le=6)


class InitTicketRequest(BaseModel):
    transaction_id: str
    item_id: str
    provider_id: str = Field(default="P1")
    passenger_name: str
    passenger_phone: str
    passenger_email: Optional[str] = None
    passenger_count: int = Field(default=1, ge=1, le=6)


class StatusRequest(BaseModel):
    transaction_id: str
    order_id: Optional[str] = None


class CancelRequest(BaseModel):
    transaction_id: str
    order_id: Optional[str] = None
    reason_id: str = Field(default="001")
    descriptor_code: str = Field(default="SOFT_CANCEL")
    descriptor_name: str = Field(default="Ride Cancellation")


class UpdateRequest(BaseModel):
    transaction_id: str
    order_id: Optional[str] = None
    update_target: str = Field(default="order.fulfillments")
    payload: Dict[str, Any] = Field(default_factory=dict)


class RatingRequest(BaseModel):
    transaction_id: str
    order_id: Optional[str] = None
    rating_category: str = Field(default="Order")
    value: str
    feedback: Optional[str] = None


ALLOWED_ATTACHMENT_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".pdf"}

def validate_attachment_url(url: str) -> str:
    url_clean = url.strip()
    if not (url_clean.startswith("http://") or url_clean.startswith("https://")):
        raise ValueError(f"Attachment URL must start with http:// or https://: {url_clean}")
    lower_path = url_clean.split("?")[0].lower()
    if not any(lower_path.endswith(ext) for ext in ALLOWED_ATTACHMENT_EXTS):
        raise ValueError(f"Attachment format not allowed. Must be one of {sorted(list(ALLOWED_ATTACHMENT_EXTS))}: {url_clean}")
    return url_clean


class IssueCreateRequest(BaseModel):
    transaction_id: Optional[str] = None
    order_id: Optional[str] = None
    category: str = Field(default="FULFILLMENT", min_length=1, max_length=80)
    description: str = Field(min_length=1, max_length=2000)
    attachments: Optional[List[str]] = Field(default=None)
    send_to_network: bool = False


class IssueUpdateRequest(BaseModel):
    status: IssueStatus
    resolution: Optional[str] = None
    note: Optional[str] = None
    attachments: Optional[List[str]] = Field(default=None)


class IssueRespondRequest(BaseModel):
    action_type: str = Field(description="Action code e.g. INFO_PROVIDED, RESOLUTION_ACCEPTED, RESOLUTION_REJECTED, ESCALATED, CLOSED")
    note: Optional[str] = None
    rating: Optional[str] = None
    attachments: Optional[List[str]] = Field(default=None)


class ReconCreateRequest(BaseModel):
    transaction_id: Optional[str] = None
    order_id: Optional[str] = None
    payment_txn_id: Optional[str] = None
    buyer_finder_fee: Decimal = Decimal("0.00")
    settlement_party: Optional[str] = None
    settlement_amount: Decimal = Decimal("0.00")
    settlement_reference: Optional[str] = None
    refund_adjustment: Decimal = Decimal("0.00")
    status: ReconStatus = ReconStatus.PENDING
    details: Dict[str, Any] = Field(default_factory=dict)


class PayoutCreateRequest(BaseModel):
    recon_id: Optional[str] = None
    transaction_id: Optional[str] = None
    order_id: Optional[str] = None
    settlement_party: Optional[str] = None
    amount: Decimal = Decimal("0.00")
    currency: str = "INR"
    payout_reference: Optional[str] = None
    status: PayoutStatus = PayoutStatus.PENDING
    details: Dict[str, Any] = Field(default_factory=dict)
    send_to_network: bool = False


@router.post("/search")
async def search_routes(
    req: SearchRouteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    """
    Search available metro tickets between origin and destination stations.
    Returns 200 OK with message_id and transaction_id. Async results pushed via SSE.
    """
    orchestrator = BecknOrchestrator(db, redis)
    res = await orchestrator.initiate_search(
        user_id=current_user.id,
        origin_station_id=req.origin_station_id,
        destination_station_id=req.destination_station_id,
        origin_gps=req.origin_gps,
        destination_gps=req.destination_gps,
        city_code=req.city_code,
        gateway_url=req.gateway_url,
        transaction_id=uuid.UUID(req.transaction_id) if req.transaction_id else None,
    )
    return res


@router.post("/select")
async def select_ticket(
    req: SelectTicketRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    """
    Select ticket option and apply reward points. Locks points in 2PC status HELD.
    Optionally applies a wallet-minted promo code; discount is capped at 50%
    of the fare.
    """
    from app.db.models import PromoCode, PromoCodeStatus
    from datetime import datetime, timezone

    orchestrator = BecknOrchestrator(db, redis)
    try:
        txn_uuid = uuid.UUID(req.transaction_id)
        res = await orchestrator.initiate_select(
            user_id=current_user.id,
            transaction_id=txn_uuid,
            item_id=req.item_id,
            provider_id=req.provider_id,
            passenger_count=req.passenger_count,
            reward_points_to_redeem=req.reward_points_to_redeem
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Optional promo code — apply on top of anything /select already priced.
    if req.promo_code:
        code_str = req.promo_code.strip().upper()
        promo = (await db.execute(
            select(PromoCode).where(
                PromoCode.code == code_str,
                PromoCode.user_id == current_user.id,
            )
        )).scalar_one_or_none()

        if promo is None:
            raise HTTPException(status_code=404, detail="Promo code not found for this user.")
        if promo.status != PromoCodeStatus.ACTIVE:
            raise HTTPException(status_code=400, detail=f"Promo code is {promo.status.value}.")
        if promo.expires_at <= datetime.now(timezone.utc):
            promo.status = PromoCodeStatus.EXPIRED
            await db.commit()
            raise HTTPException(status_code=400, detail="Promo code has expired.")

        txn_row = (await db.execute(select(Transaction).where(Transaction.transaction_id == txn_uuid))).scalar_one()
        fare = txn_row.total_base_fare + (txn_row.tax_amount or Decimal("0"))
        max_off = (fare * Decimal("0.5")).quantize(Decimal("0.01"))
        applied = min(promo.value_inr, max_off)

        # Bookmark the promo id on the txn — the Razorpay-order endpoint reads
        # it back to compute the net-to-charge. We reuse rewards_discount_amount
        # because that's already what Razorpay/confirm subtract from the fare.
        existing_discount = txn_row.rewards_discount_amount or Decimal("0")
        txn_row.rewards_discount_amount = existing_discount + applied
        promo.status = PromoCodeStatus.USED
        promo.redeemed_at = datetime.now(timezone.utc)
        promo.redeemed_txn_id = txn_uuid
        await db.commit()

        res["promo_code"] = {
            "code": promo.code,
            "value_inr": f"{promo.value_inr:.2f}",
            "applied_inr": f"{applied:.2f}",
        }

    return res


@router.post("/confirm")
async def confirm_ticket_payment(
    req: ConfirmPaymentRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    """
    Confirms ticket purchase after Razorpay reports a successful charge.

    Order of operations:
      1. Verify the Razorpay signature server-side — the client cannot forge
         a payment.
      2. Send /confirm to the BPP (amount is derived from the txn quote).
      3. Persist a Ticket row with a fresh Ed25519-signed QR token.
      4. Return the ticket for the client to render.

    Idempotent per `transaction_id`: a repeat call returns the already-issued
    ticket instead of double-booking.
    """
    from app.api.v1.payments import verify_razorpay_signature
    from app.security.qr_token import issue_qr_token
    from app.db.models import Ticket, TicketStatus
    from datetime import datetime, timezone, timedelta

    if not verify_razorpay_signature(
        req.razorpay_order_id, req.razorpay_payment_id, req.razorpay_signature
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid payment signature")

    try:
        txn_uuid = uuid.UUID(req.transaction_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    # Idempotency: return existing ticket if we've already confirmed this txn.
    existing = await db.execute(
        select(Ticket).where(Ticket.transaction_id == txn_uuid, Ticket.user_id == current_user.id)
    )
    already = existing.scalar_one_or_none()
    if already is not None:
        from app.db.models import PointsLedger, LedgerEntryType
        prior = await db.execute(
            select(PointsLedger).where(
                PointsLedger.transaction_id == txn_uuid,
                PointsLedger.user_id == current_user.id,
                PointsLedger.entry_type == LedgerEntryType.EARNED,
            )
        )
        prior_row = prior.scalar_one_or_none()
        return await _serialize_ticket(
            db, already,
            points_earned=int(prior_row.points_amount) if prior_row else 0,
        )

    orchestrator = BecknOrchestrator(db, redis)
    try:
        await orchestrator.initiate_confirm(
            user_id=current_user.id,
            transaction_id=txn_uuid,
            payment_txn_id=req.razorpay_payment_id,
            item_id=req.item_id,
            provider_id=req.provider_id,
            passenger_count=req.passenger_count,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    txn_row = await db.execute(select(Transaction).where(Transaction.transaction_id == txn_uuid))
    txn = txn_row.scalar_one()

    now = datetime.now(timezone.utc)
    valid_until = now + timedelta(hours=settings.QR_TOKEN_TTL_HOURS)
    ticket = Ticket(
        transaction_id=txn_uuid,
        user_id=current_user.id,
        metro_operator_id=txn.bpp_id or "unknown",
        origin_station_id="",  # populated by on_confirm callback with real stop info
        destination_station_id="",
        passenger_count=req.passenger_count,
        qr_payload="",
        valid_from=now,
        valid_until=valid_until,
        status=TicketStatus.ISSUED,
    )
    db.add(ticket)
    await db.flush()

    token, exp = issue_qr_token(
        ticket_id=str(ticket.ticket_id),
        order_id=str(ticket.ticket_id),
        transaction_id=req.transaction_id,
        user_id=str(current_user.id),
    )
    ticket.qr_payload = token
    await db.commit()
    await db.refresh(ticket)

    # Credit reward points for this ticket. Idempotent on (user, txn) so a
    # retry of /confirm won't double-credit.
    from app.ledger.rewards import RewardsLedgerManager
    from app.api.v1.rewards import credit_referral_on_first_ticket
    rewards = RewardsLedgerManager(db, redis)
    fare_for_award = txn.final_user_paid_amount or Decimal("0")
    points_earned = await rewards.award_points_for_ticket(
        user_id=current_user.id,
        transaction_id=txn_uuid,
        fare_inr=fare_for_award,
    )
    await db.commit()
    # Credit any pending referral (both parties get points on the referred
    # user's first successful ticket). Idempotent — subsequent confirms are
    # no-ops because activated_at gets set.
    await credit_referral_on_first_ticket(db, current_user.id, txn_uuid)

    return await _serialize_ticket(db, ticket, points_earned=points_earned)


async def _serialize_ticket(db, ticket, points_earned: int = 0):
    txn_row = await db.execute(select(Transaction).where(Transaction.transaction_id == ticket.transaction_id))
    txn = txn_row.scalar_one_or_none()
    total_fare = float((txn.final_user_paid_amount or Decimal("0"))) if txn else 0.0
    return {
        "ticket": {
            "ticket_id": str(ticket.ticket_id),
            "order_id": str(ticket.ticket_id),
            "transaction_id": str(ticket.transaction_id),
            "origin_station": ticket.origin_station_id or "Origin",
            "destination_station": ticket.destination_station_id or "Destination",
            "ticket_type": "SJT",
            "passenger_count": ticket.passenger_count,
            "total_fare": total_fare,
            "points_earned": points_earned,
            "qr_payload": ticket.qr_payload,
            "issued_at": ticket.valid_from.isoformat(),
            "expires_at": ticket.valid_until.isoformat(),
            "status": ticket.status.value if hasattr(ticket.status, "value") else str(ticket.status),
        }
    }


@router.post("/init")
async def init_ticket_order(
    req: InitTicketRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_init(
            user_id=current_user.id,
            transaction_id=uuid.UUID(req.transaction_id),
            item_id=req.item_id,
            provider_id=req.provider_id,
            passenger_name=req.passenger_name,
            passenger_phone=req.passenger_phone,
            passenger_email=req.passenger_email,
            passenger_count=req.passenger_count,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/status")
async def check_ticket_status(
    req: StatusRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_status(current_user.id, uuid.UUID(req.transaction_id), req.order_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/cancel")
async def cancel_ticket_order(
    req: CancelRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_cancel(
            current_user.id,
            uuid.UUID(req.transaction_id),
            req.order_id,
            req.reason_id,
            req.descriptor_code,
            req.descriptor_name,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/support")
async def request_order_support(
    req: StatusRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_support(current_user.id, uuid.UUID(req.transaction_id), req.order_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/update")
async def update_ticket_order(
    req: UpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_update(
            current_user.id,
            uuid.UUID(req.transaction_id),
            req.order_id,
            req.update_target,
            req.payload,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/track")
async def track_ticket_order(
    req: StatusRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_track(current_user.id, uuid.UUID(req.transaction_id), req.order_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/rating")
async def rate_ticket_order(
    req: RatingRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_rating(
            current_user.id,
            uuid.UUID(req.transaction_id),
            req.order_id,
            req.rating_category,
            req.value,
            req.feedback,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/issues", status_code=status.HTTP_201_CREATED)
async def create_issue(
    req: IssueCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    validated_attachments = []
    if req.attachments:
        for url in req.attachments:
            try:
                validated_attachments.append(validate_attachment_url(url))
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    trail_entry = {"status": IssueStatus.OPEN.value, "note": req.description}
    if validated_attachments:
        trail_entry["attachments"] = validated_attachments

    issue = Issue(
        transaction_id=req.transaction_id,
        order_id=req.order_id,
        category=req.category,
        description=req.description,
        trail=[trail_entry],
    )
    db.add(issue)
    await db.commit()
    await db.refresh(issue)
    if req.send_to_network:
        orchestrator = BecknOrchestrator(db, redis)
        transaction_id = uuid.UUID(req.transaction_id) if req.transaction_id else None
        return await orchestrator.initiate_issue(current_user.id, issue, transaction_id)
    return issue


@router.get("/issues")
async def list_issues(
    issue_status: Optional[str] = Query(default=None, alias="status"),
    category: Optional[str] = None,
    transaction_id: Optional[str] = None,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db)
):
    query = select(Issue)
    if issue_status:
        try:
            enum_val = IssueStatus(issue_status.upper())
            query = query.where(Issue.status == enum_val)
        except ValueError:
            pass
    if category:
        query = query.where(Issue.category == category)
    if transaction_id:
        query = query.where(Issue.transaction_id == transaction_id)

    query = query.order_by(Issue.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/issues/{issue_id}")
async def get_issue(
    issue_id: str,
    db: AsyncSession = Depends(get_db)
):
    try:
        issue_uuid = uuid.UUID(issue_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid issue_id UUID format")
    result = await db.execute(select(Issue).where(Issue.issue_id == issue_uuid))
    issue = result.scalar_one_or_none()
    if not issue:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Issue not found")
    return issue


@router.patch("/issues/{issue_id}")
async def update_issue(issue_id: str, req: IssueUpdateRequest, db: AsyncSession = Depends(get_db)):
    try:
        issue_uuid = uuid.UUID(issue_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid issue_id UUID format")
    result = await db.execute(select(Issue).where(Issue.issue_id == issue_uuid))
    issue = result.scalar_one_or_none()
    if not issue:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Issue not found")

    validated_attachments = []
    if req.attachments:
        for url in req.attachments:
            try:
                validated_attachments.append(validate_attachment_url(url))
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    trail = list(issue.trail or [])
    trail_entry = {"status": req.status.value, "note": req.note or req.resolution or ""}
    if validated_attachments:
        trail_entry["attachments"] = validated_attachments
    trail.append(trail_entry)

    issue.status = req.status
    issue.resolution = req.resolution or issue.resolution
    issue.trail = trail
    await db.commit()
    await db.refresh(issue)
    return issue


@router.post("/issues/{issue_id}/respond")
async def respond_to_issue(
    issue_id: str,
    req: IssueRespondRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    try:
        issue_uuid = uuid.UUID(issue_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid issue_id UUID format")
    result = await db.execute(select(Issue).where(Issue.issue_id == issue_uuid))
    issue = result.scalar_one_or_none()
    if not issue:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Issue not found")

    validated_attachments = []
    if req.attachments:
        for url in req.attachments:
            try:
                validated_attachments.append(validate_attachment_url(url))
            except ValueError as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    orchestrator = BecknOrchestrator(db, redis)
    note_text = req.note or f"Action {req.action_type} executed."
    if validated_attachments:
        note_text += f" Attachments: {', '.join(validated_attachments)}"

    try:
        return await orchestrator.respond_to_issue(
            user_id=current_user.id,
            issue=issue,
            action_type=req.action_type,
            note=note_text,
            rating=req.rating
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/issues/{issue_id}/status")
async def request_issue_status(
    issue_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    try:
        issue_uuid = uuid.UUID(issue_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid issue_id UUID format")
    result = await db.execute(select(Issue).where(Issue.issue_id == issue_uuid))
    issue = result.scalar_one_or_none()
    if not issue:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Issue not found")
    orchestrator = BecknOrchestrator(db, redis)
    try:
        return await orchestrator.initiate_issue_status(current_user.id, issue)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/recon", status_code=status.HTTP_201_CREATED)
async def create_recon_record(
    req: ReconCreateRequest,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client),
    submit_to_network: bool = Query(default=False)
):
    record = ReconRecord(**req.model_dump())
    db.add(record)
    await db.commit()
    await db.refresh(record)
    if submit_to_network:
        orchestrator = BecknOrchestrator(db, redis)
        return await orchestrator.initiate_receiver_recon(record)
    return record


@router.get("/recon")
async def list_recon_records(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ReconRecord).order_by(ReconRecord.created_at.desc()))
    return result.scalars().all()


@router.patch("/recon/{recon_id}")
async def update_recon_record(recon_id: str, req: ReconCreateRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ReconRecord).where(ReconRecord.recon_id == uuid.UUID(recon_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recon record not found")
    for key, value in req.model_dump().items():
        setattr(record, key, value)
    await db.commit()
    await db.refresh(record)
    return record


@router.post("/recon/{recon_id}/receiver-recon")
async def submit_receiver_recon(recon_id: str, db: AsyncSession = Depends(get_db), redis: Redis = Depends(get_redis_client)):
    result = await db.execute(select(ReconRecord).where(ReconRecord.recon_id == uuid.UUID(recon_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recon record not found")
    orchestrator = BecknOrchestrator(db, redis)
    return await orchestrator.initiate_receiver_recon(record)


@router.post("/payouts", status_code=status.HTTP_201_CREATED)
async def create_payout_record(
    req: PayoutCreateRequest,
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis_client)
):
    payload = {k: v for k, v in req.model_dump().items() if k != "send_to_network"}
    if payload.get("recon_id"):
        payload["recon_id"] = uuid.UUID(payload["recon_id"])
    record = PayoutRecord(**payload)
    db.add(record)
    await db.commit()
    await db.refresh(record)
    if req.send_to_network:
        orchestrator = BecknOrchestrator(db, redis)
        return await orchestrator.initiate_settle(record)
    return record


@router.get("/payouts")
async def list_payout_records(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PayoutRecord).order_by(PayoutRecord.created_at.desc()))
    return result.scalars().all()


@router.patch("/payouts/{payout_id}")
async def update_payout_record(payout_id: str, req: PayoutCreateRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PayoutRecord).where(PayoutRecord.payout_id == uuid.UUID(payout_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payout record not found")
    for key, value in req.model_dump().items():
        if key != "send_to_network":
            if key == "recon_id" and value:
                value = uuid.UUID(value)
            setattr(record, key, value)
    await db.commit()
    await db.refresh(record)
    return record


@router.post("/payouts/{payout_id}/settle")
async def submit_settlement(payout_id: str, db: AsyncSession = Depends(get_db), redis: Redis = Depends(get_redis_client)):
    result = await db.execute(select(PayoutRecord).where(PayoutRecord.payout_id == uuid.UUID(payout_id)))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Payout record not found")
    orchestrator = BecknOrchestrator(db, redis)
    return await orchestrator.initiate_settle(record)


@router.get("/observability")
async def list_observability_events(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ObservabilityEvent).order_by(ObservabilityEvent.created_at.desc()).limit(200))
    return result.scalars().all()


@router.post("/observability/submit")
async def submit_observability_events(db: AsyncSession = Depends(get_db)):
    if not settings.NETWORK_OBSERVABILITY_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="NETWORK_OBSERVABILITY_TOKEN is not configured",
        )

    result = await db.execute(
        select(ObservabilityEvent)
        .where(ObservabilityEvent.submitted == 0)
        .order_by(ObservabilityEvent.created_at.asc())
        .limit(200)
    )
    events = result.scalars().all()
    if not events:
        return {"submitted": 0, "status": "NO_PENDING_EVENTS"}

    logs = [
        {
            "subscriber_id": settings.BAP_ID,
            "subscriber_type": "BAP",
            "domain": settings.ONDC_DOMAIN,
            "version": settings.ONDC_CORE_VERSION,
            "environment": settings.ONDC_ENVIRONMENT,
            "transaction_id": event.transaction_id,
            "message_id": event.message_id,
            "action": event.action,
            "created_at": event.created_at.isoformat() if event.created_at else None,
            "payload": _scrub_observability_value(event.payload),
        }
        for event in events
    ]

    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            response = await client.post(
                settings.NETWORK_OBSERVABILITY_URL,
                json=logs,
                headers={
                    "Authorization": f"Bearer {settings.NETWORK_OBSERVABILITY_TOKEN}",
                    "Content-Type": "application/json",
                },
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={
                    "status": "OBSERVABILITY_SUBMISSION_FAILED",
                    "http_status": exc.response.status_code,
                    "response": exc.response.text[:1000],
                },
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={
                    "status": "OBSERVABILITY_SUBMISSION_FAILED",
                    "error": str(exc),
                },
            )

    for event in events:
        event.submitted = 1
    await db.commit()
    return {"submitted": len(events), "status": "SUBMITTED"}


@router.get("/compliance/readiness")
async def integration_component_readiness(db: AsyncSession = Depends(get_db)):
    tx_count = (await db.execute(select(Transaction).limit(1))).scalars().first() is not None
    protocol_actions = [row[0] for row in (await db.execute(select(ProtocolMessage.action).distinct())).all()]
    issue_count = (await db.execute(select(Issue).limit(1))).scalars().first() is not None
    recon_count = (await db.execute(select(ReconRecord).limit(1))).scalars().first() is not None
    payout_count = (await db.execute(select(PayoutRecord).limit(1))).scalars().first() is not None
    obs_count = (await db.execute(select(ObservabilityEvent).limit(1))).scalars().first() is not None
    required_callbacks = {
        "on_search", "on_select", "on_init", "on_confirm", "on_status",
        "on_cancel", "on_update", "on_track", "on_support", "on_rating",
        "on_issue", "on_issue_status", "on_receiver_recon", "on_settle",
    }
    required_outbound = {
        "search", "select", "init", "confirm", "status", "cancel",
        "support", "update", "track", "rating", "issue", "issue_status",
        "receiver_recon", "settle",
    }
    return {
        "subscriber": {"bap_id": settings.BAP_ID, "bap_uri": settings.BAP_URI},
        "components": {
            "transaction_flows": {
                "built": True,
                "evidence_seen": tx_count,
                "outbound_actions": sorted(required_outbound.intersection(protocol_actions)),
                "callback_actions": sorted(required_callbacks.intersection(protocol_actions)),
            },
            "issue_grievance_management": {
                "built": True,
                "evidence_seen": issue_count or any(action in protocol_actions for action in {"issue", "issue_status", "on_issue", "on_issue_status"}),
                "apis": ["/api/v1/issues", "/api/v1/issues/{issue_id}/status", "/ondc/on_issue", "/ondc/on_issue_status"],
            },
            "reconciliation_settlement_payouts": {
                "built": True,
                "evidence_seen": recon_count or payout_count or any(action in protocol_actions for action in {"receiver_recon", "settle", "on_receiver_recon", "on_settle"}),
                "apis": ["/api/v1/recon", "/api/v1/recon/{recon_id}/receiver-recon", "/api/v1/payouts", "/api/v1/payouts/{payout_id}/settle"],
            },
            "network_observability": {
                "built": True,
                "evidence_seen": obs_count,
                "token_configured": bool(settings.NETWORK_OBSERVABILITY_TOKEN),
                "submission_url": settings.NETWORK_OBSERVABILITY_URL,
                "apis": ["/api/v1/observability", "/api/v1/observability/submit"],
            },
        },
        "portal_blockers": [
            "ONDC portal generated verification HTML must replace placeholder content",
            "Use durable PostgreSQL/Redis before production traffic; current Cloud Run setup is single-instance pre-prod smoke-test storage",
        ],
    }


@router.get("/tickets")
async def list_user_tickets(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Retrieves all issued tickets for the authenticated user.
    """
    stmt = select(Ticket).where(Ticket.user_id == current_user.id).order_by(Ticket.created_at.desc())
    result = await db.execute(stmt)
    tickets = result.scalars().all()
    return tickets


@router.get("/events/{transaction_id}")
async def sse_ticket_stream(
    transaction_id: str,
    request: Request,
    redis: Redis = Depends(get_redis_client)
):
    """
    Server-Sent Events (SSE) live push stream for real-time mobile updates.
    """
    sse_mgr = SSEManager(redis)
    return EventSourceResponse(sse_mgr.event_generator(transaction_id, request))
