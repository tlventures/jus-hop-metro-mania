import uuid
import enum
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    String,
    BigInteger,
    Numeric,
    Integer,
    Text,
    DateTime,
    ForeignKey,
    Enum as SQLEnum,
    Index,
    CheckConstraint,
    JSON,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.session import Base


class OndcTxnStatus(str, enum.Enum):
    SEARCHED = "SEARCHED"
    SELECTED = "SELECTED"
    INITIATED = "INITIATED"
    PAID = "PAID"
    CONFIRMED = "CONFIRMED"
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"


class TicketStatus(str, enum.Enum):
    ISSUED = "ISSUED"
    USED = "USED"
    EXPIRED = "EXPIRED"
    REFUNDED = "REFUNDED"
    CANCELLED = "CANCELLED"


class LedgerEntryType(str, enum.Enum):
    EARNED = "EARNED"
    HELD = "HELD"
    REDEEMED = "REDEEMED"
    RELEASED = "RELEASED"


class IssueStatus(str, enum.Enum):
    OPEN = "OPEN"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    PROCESSING = "PROCESSING"
    RESOLVED = "RESOLVED"
    CLOSED = "CLOSED"


class ReconStatus(str, enum.Enum):
    PENDING = "PENDING"
    RECONCILED = "RECONCILED"
    DISPUTED = "DISPUTED"
    SETTLED = "SETTLED"


class PayoutStatus(str, enum.Enum):
    PENDING = "PENDING"
    INITIATED = "INITIATED"
    PAID = "PAID"
    FAILED = "FAILED"
    REVERSED = "REVERSED"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone_number_hash = Column(String(64), unique=True, nullable=False, index=True)
    reward_points_balance = Column(BigInteger, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    transactions = relationship("Transaction", back_populates="user", cascade="all, delete-orphan")
    tickets = relationship("Ticket", back_populates="user", cascade="all, delete-orphan")
    ledger_entries = relationship("PointsLedger", back_populates="user", cascade="all, delete-orphan")

    __table_args__ = (
        CheckConstraint("reward_points_balance >= 0", name="chk_reward_points_balance_positive"),
    )


class Transaction(Base):
    __tablename__ = "transactions"

    transaction_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    city_code = Column(String(16), nullable=False)
    bpp_id = Column(String(255), nullable=False)
    bpp_uri = Column(String(512), nullable=False)
    status = Column(SQLEnum(OndcTxnStatus, name="ondc_txn_status"), default=OndcTxnStatus.SEARCHED, nullable=False)
    total_base_fare = Column(Numeric(10, 2), nullable=False, default=0.00)
    tax_amount = Column(Numeric(10, 2), default=0.00)
    rewards_discount_amount = Column(Numeric(10, 2), default=0.00)
    final_user_paid_amount = Column(Numeric(10, 2), default=0.00)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="transactions")
    tickets = relationship("Ticket", back_populates="transaction", cascade="all, delete-orphan")
    ledger_entries = relationship("PointsLedger", back_populates="transaction", cascade="all, delete-orphan")


class Ticket(Base):
    __tablename__ = "tickets"

    ticket_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(UUID(as_uuid=True), ForeignKey("transactions.transaction_id"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    metro_operator_id = Column(String(128), nullable=False)
    origin_station_id = Column(String(128), nullable=False)
    destination_station_id = Column(String(128), nullable=False)
    passenger_count = Column(Integer, default=1)
    qr_payload = Column(Text, nullable=False)
    valid_from = Column(DateTime(timezone=True), nullable=False)
    valid_until = Column(DateTime(timezone=True), nullable=False)
    status = Column(SQLEnum(TicketStatus, name="ticket_status"), default=TicketStatus.ISSUED, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    transaction = relationship("Transaction", back_populates="tickets")
    user = relationship("User", back_populates="tickets")

    __table_args__ = (
        Index("idx_tickets_user_status", "user_id", "status"),
    )


class PointsLedger(Base):
    __tablename__ = "points_ledger"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    transaction_id = Column(UUID(as_uuid=True), ForeignKey("transactions.transaction_id"), nullable=True, index=True)
    points_amount = Column(BigInteger, nullable=False)
    entry_type = Column(SQLEnum(LedgerEntryType, name="ledger_entry_type"), nullable=False)
    # Source of the credit (which earn surface). Populated for EARNED rows.
    # Values: TICKET, AD_WATCH, DAILY_STREAK, REFERRAL_REFERRER, REFERRAL_REFERRED,
    # ARTICLE_READ, QUIZ_COMPLETE, GAME_WIN, DAILY_QUEST, PROMO_CODE, ...
    source = Column(String(32), nullable=True, index=True)
    # Idempotency key — one earn per (user, event_id). Null-ok for legacy rows.
    event_id = Column(String(128), nullable=True)
    # Only set on EARNED rows — points are void after this instant. NULL means
    # no expiry (legacy). New EARNED rows always set +6 months.
    expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="ledger_entries")
    transaction = relationship("Transaction", back_populates="ledger_entries")

    __table_args__ = (
        Index("idx_ledger_user_txn", "user_id", "transaction_id"),
        Index("idx_ledger_user_type_exp", "user_id", "entry_type", "expires_at"),
        Index("idx_ledger_user_source_created", "user_id", "source", "created_at"),
        # Idempotency: same (user, event_id) can only appear once.
        Index("uq_ledger_user_event", "user_id", "event_id", unique=True,
              postgresql_where=(event_id.isnot(None))),
    )


class StreakRecord(Base):
    """Daily-open streak per user. One row per user, updated on each claim."""
    __tablename__ = "streak_records"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    current_day = Column(Integer, default=0, nullable=False)
    longest_day = Column(Integer, default=0, nullable=False)
    last_claimed_on = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))


class ReferralLink(Base):
    """User's shareable code (auto-created lazily on first GET)."""
    __tablename__ = "referral_links"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    code = Column(String(32), unique=True, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class ReferralRedemption(Base):
    """One row per referred user — enforces one-time referral per user."""
    __tablename__ = "referral_redemptions"

    referred_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    referrer_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    referrer_code = Column(String(32), nullable=False)
    applied_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    # Set when the referred user's first ticket confirms — both parties credited.
    activated_at = Column(DateTime(timezone=True), nullable=True)


class PromoCodeStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    USED = "USED"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class PromoCode(Base):
    """User-owned promo code minted by converting reward points at the wallet.

    Each code represents a fixed INR discount; on apply at /select we cap the
    actual discount at min(code.value_inr, fare * 50%) and mark the code USED.
    """
    __tablename__ = "promo_codes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    code = Column(String(32), unique=True, nullable=False, index=True)
    value_inr = Column(Numeric(10, 2), nullable=False)
    points_burnt = Column(BigInteger, nullable=False)
    status = Column(SQLEnum(PromoCodeStatus, name="promo_code_status"),
                    default=PromoCodeStatus.ACTIVE, nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at = Column(DateTime(timezone=True), nullable=False)
    redeemed_at = Column(DateTime(timezone=True), nullable=True)
    redeemed_txn_id = Column(UUID(as_uuid=True),
                             ForeignKey("transactions.transaction_id"),
                             nullable=True)

    __table_args__ = (
        Index("idx_promo_user_status", "user_id", "status"),
    )


class ProtocolMessage(Base):
    __tablename__ = "protocol_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(String(64), nullable=True, index=True)
    message_id = Column(String(128), nullable=True, index=True)
    action = Column(String(64), nullable=False, index=True)
    direction = Column(String(16), nullable=False)
    subscriber_id = Column(String(255), nullable=True)
    bap_id = Column(String(255), nullable=True)
    bap_uri = Column(String(512), nullable=True)
    bpp_id = Column(String(255), nullable=True)
    bpp_uri = Column(String(512), nullable=True)
    domain = Column(String(32), nullable=True)
    city = Column(String(16), nullable=True)
    http_status = Column(Integer, nullable=True)
    ack_status = Column(String(16), nullable=True)
    error_code = Column(String(64), nullable=True)
    latency_ms = Column(Integer, nullable=True)
    payload = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Issue(Base):
    __tablename__ = "issues"

    issue_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(String(64), nullable=True, index=True)
    order_id = Column(String(128), nullable=True, index=True)
    category = Column(String(80), nullable=False)
    status = Column(SQLEnum(IssueStatus, name="issue_status"), default=IssueStatus.OPEN, nullable=False)
    description = Column(Text, nullable=False)
    resolution = Column(Text, nullable=True)
    trail = Column(JSON, nullable=False, default=list)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class ReconRecord(Base):
    __tablename__ = "recon_records"

    recon_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(String(64), nullable=True, index=True)
    order_id = Column(String(128), nullable=True, index=True)
    payment_txn_id = Column(String(128), nullable=True, index=True)
    buyer_finder_fee = Column(Numeric(10, 2), default=0.00)
    settlement_party = Column(String(128), nullable=True)
    settlement_amount = Column(Numeric(10, 2), default=0.00)
    settlement_reference = Column(String(128), nullable=True)
    refund_adjustment = Column(Numeric(10, 2), default=0.00)
    status = Column(SQLEnum(ReconStatus, name="recon_status"), default=ReconStatus.PENDING, nullable=False)
    details = Column(JSON, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class PayoutRecord(Base):
    __tablename__ = "payout_records"

    payout_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    recon_id = Column(UUID(as_uuid=True), nullable=True, index=True)
    transaction_id = Column(String(64), nullable=True, index=True)
    order_id = Column(String(128), nullable=True, index=True)
    settlement_party = Column(String(128), nullable=True)
    amount = Column(Numeric(10, 2), default=0.00)
    currency = Column(String(8), default="INR", nullable=False)
    payout_reference = Column(String(128), nullable=True, index=True)
    status = Column(SQLEnum(PayoutStatus, name="payout_status"), default=PayoutStatus.PENDING, nullable=False)
    details = Column(JSON, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class ObservabilityEvent(Base):
    __tablename__ = "observability_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_id = Column(String(64), nullable=True, index=True)
    message_id = Column(String(128), nullable=True, index=True)
    action = Column(String(64), nullable=False, index=True)
    payload = Column(JSON, nullable=False)
    submitted = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
