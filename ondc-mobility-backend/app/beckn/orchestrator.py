import uuid
import datetime
import json
from decimal import Decimal, ROUND_HALF_UP
from typing import Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from redis.asyncio import Redis

from app.core.config import settings
from app.core.logging import logger
from app.db.models import (
    Transaction,
    Ticket,
    User,
    OndcTxnStatus,
    TicketStatus,
    ProtocolMessage,
    ObservabilityEvent,
    Issue,
    IssueStatus,
    ReconRecord,
    ReconStatus,
    PayoutRecord,
    PayoutStatus,
)
from app.ledger.rewards import RewardsLedgerManager
from app.beckn.client import beckn_client
from app.workers.sse import SSEManager
from app.resilience.circuit_breaker import get_bpp_circuit_breaker


## Server-side price catalog.
## The BPP's on_select callback is the authoritative source of price. Until we
## fully consume it, keep a small server-owned catalog so /select can persist a
## priced quote for the Razorpay order-creation step. Do NOT accept prices from
## the client — that's the whole point of moving them here.
_CATALOG_UNIT_PRICE_INR: Dict[str, Decimal] = {
    "I1": Decimal("35.00"),  # Single Journey Ticket
    "I2": Decimal("60.00"),  # Return Journey Ticket
}
BUYER_FINDER_FEES_PERCENTAGE = Decimal("1")


def _catalog_price(item_id: str) -> Decimal:
    price = _CATALOG_UNIT_PRICE_INR.get(item_id)
    if price is None:
        raise ValueError(f"Unknown catalog item_id: {item_id!r}")
    return price


class BecknOrchestrator:
    """
    Core Business Orchestrator handling client intent conversion into Beckn TRV11 protocol calls
    and processing incoming asynchronous BPP callbacks.
    """

    def __init__(self, db: AsyncSession, redis: Redis):
        self.db = db
        self.redis = redis
        self.rewards_mgr = RewardsLedgerManager(db, redis)
        self.sse_mgr = SSEManager(redis)

    def _timestamp(self) -> str:
        now = datetime.datetime.now(datetime.timezone.utc)
        return now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    def _city_from_context(self, context: Dict[str, Any]) -> Optional[str]:
        city = context.get("city")
        if city:
            return city
        location = context.get("location", {})
        if isinstance(location, dict):
            city_obj = location.get("city", {})
            if isinstance(city_obj, dict):
                return city_obj.get("code") or city_obj.get("name")
        return None

    def _context(
        self,
        action: str,
        transaction_id: uuid.UUID,
        city_code: str = "std:040",
        bpp_id: Optional[str] = None,
        bpp_uri: Optional[str] = None,
    ) -> Dict[str, Any]:
        context = {
            "domain": settings.ONDC_DOMAIN,
            "location": {
                "country": {"code": settings.ONDC_COUNTRY},
                "city": {"code": city_code},
            },
            "action": action,
            "version": settings.ONDC_CORE_VERSION,
            "bap_id": settings.BAP_ID,
            "bap_uri": settings.BAP_URI,
            "transaction_id": str(transaction_id),
            "message_id": str(uuid.uuid4()),
            "timestamp": self._timestamp(),
            "ttl": "PT30S",
        }
        if bpp_id:
            context["bpp_id"] = bpp_id
        if bpp_uri:
            context["bpp_uri"] = bpp_uri.replace("//seller", "/seller")
        return context

    def _settlement_amount(self, amount: Optional[Any]) -> Optional[str]:
        if amount is None:
            return None
        gross = Decimal(str(amount))
        fee = (gross * BUYER_FINDER_FEES_PERCENTAGE / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        net = (gross - fee).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        return format(net, ".2f")

    def _issue_sub_category(self, category: Optional[str]) -> str:
        category_upper = str(category or "").upper()
        if category_upper == "ORDER":
            return "ORD101"
        if category_upper == "PAYMENT":
            return "PMT101"
        return "FLM101"

    async def _payment_id_from_on_init(self, transaction_id: uuid.UUID) -> str:
        stmt = (
            select(ProtocolMessage)
            .where(
                ProtocolMessage.transaction_id == str(transaction_id),
                ProtocolMessage.direction == "inbound",
                ProtocolMessage.action == "on_init",
            )
            .order_by(ProtocolMessage.created_at.desc())
        )
        result = await self.db.execute(stmt)
        msg = result.scalars().first()
        payments = (
            ((msg.payload or {}).get("message") or {}).get("order", {}).get("payments", [])
            if msg
            else []
        )
        if isinstance(payments, list) and payments and isinstance(payments[0], dict) and payments[0].get("id"):
            return str(payments[0]["id"])
        return "PA1"

    async def record_protocol_message(
        self,
        payload: Dict[str, Any],
        *,
        direction: str,
        http_status: Optional[int] = None,
        ack_status: Optional[str] = None,
        latency_ms: Optional[int] = None,
    ) -> None:
        context = payload.get("context", {})
        error = payload.get("error", {})
        self.db.add(ProtocolMessage(
            transaction_id=context.get("transaction_id"),
            message_id=context.get("message_id"),
            action=context.get("action", "unknown"),
            direction=direction,
            subscriber_id=context.get("bpp_id") or context.get("bap_id"),
            bap_id=context.get("bap_id"),
            bap_uri=context.get("bap_uri"),
            bpp_id=context.get("bpp_id"),
            bpp_uri=context.get("bpp_uri"),
            domain=context.get("domain"),
            city=self._city_from_context(context),
            http_status=http_status,
            ack_status=ack_status,
            error_code=error.get("code") if isinstance(error, dict) else None,
            latency_ms=latency_ms,
            payload=payload,
        ))
        self.db.add(ObservabilityEvent(
            transaction_id=context.get("transaction_id"),
            message_id=context.get("message_id"),
            action=context.get("action", "unknown"),
            payload={
                "transaction_id": context.get("transaction_id"),
                "message_id": context.get("message_id"),
                "action": context.get("action"),
                "timestamp": context.get("timestamp"),
                "subscriber_id": context.get("bpp_id") or context.get("bap_id"),
                "bap_id": context.get("bap_id"),
                "bap_uri": context.get("bap_uri"),
                "bpp_id": context.get("bpp_id"),
                "bpp_uri": context.get("bpp_uri"),
                "domain": context.get("domain"),
                "city": self._city_from_context(context),
                "http_status": http_status,
                "ack_status": ack_status,
                "error_code": error.get("code") if isinstance(error, dict) else None,
                "latency_ms": latency_ms,
            },
        ))
        await self.db.commit()

    async def _send_to_bpp(self, txn: Transaction, action: str, message: Dict[str, Any]) -> Dict[str, Any]:
        payload = {
            "context": self._context(
                action,
                txn.transaction_id,
                city_code=txn.city_code,
                bpp_id=txn.bpp_id,
                bpp_uri=txn.bpp_uri,
            ),
            "message": message,
        }
        await self.record_protocol_message(payload, direction="outbound")
        cb = get_bpp_circuit_breaker(txn.bpp_uri)
        return await cb.call(beckn_client.post, url=f"{txn.bpp_uri.rstrip('/')}/{action}", payload=payload)

    def _payment_terms(self, amount: Optional[Any] = None, *, search: bool = False) -> Dict[str, Any]:
        settlement_terms = [
            {"descriptor": {"code": "DELAY_INTEREST"}, "value": "2.5"},
            {"descriptor": {"code": "STATIC_TERMS"}, "value": f"{settings.BAP_URI.rstrip('/')}/terms"},
        ]
        if not search:
            settlement_terms = [
                {"descriptor": {"code": "SETTLEMENT_WINDOW"}, "value": "PT60M"},
                {"descriptor": {"code": "SETTLEMENT_BASIS"}, "value": "Delivery"},
                {"descriptor": {"code": "SETTLEMENT_TYPE"}, "value": "NEFT"},
                {"descriptor": {"code": "MANDATORY_ARBITRATION"}, "value": "TRUE"},
                {"descriptor": {"code": "COURT_JURISDICTION"}, "value": "New Delhi"},
                *settlement_terms,
            ]
        if amount is not None and not search:
            settlement_terms.insert(0, {"descriptor": {"code": "SETTLEMENT_AMOUNT"}, "value": self._settlement_amount(amount)})

        return {
            "collected_by": "BAP",
            "tags": [
                {
                    "descriptor": {"code": "BUYER_FINDER_FEES"},
                    "display": False,
                    "list": [
                        {"descriptor": {"code": "BUYER_FINDER_FEES_PERCENTAGE"}, "value": "1"},
                        {"descriptor": {"code": "BUYER_FINDER_FEES_TYPE"}, "value": "percent"},
                    ],
                },
                {
                    "descriptor": {"code": "SETTLEMENT_TERMS"},
                    "display": False,
                    "list": settlement_terms,
                },
            ],
        }

    def _looks_like_gps(self, value: Optional[str]) -> bool:
        if not value:
            return False
        parts = [part.strip() for part in value.split(",")]
        if len(parts) != 2:
            return False
        try:
            float(parts[0])
            float(parts[1])
            return True
        except ValueError:
            return False

    def _search_message(
        self,
        origin_station_id: str,
        destination_station_id: str,
        origin_gps: Optional[str] = None,
        destination_gps: Optional[str] = None,
    ) -> Dict[str, Any]:
        fulfillment: Dict[str, Any] = {
            "vehicle": {"category": "METRO"},
        }

        is_catalog_search = (
            origin_station_id.upper() == "STATION_CODE_FLOW"
            and destination_station_id.upper() == "CATALOG"
        )
        if not is_catalog_search:
            start_gps = origin_gps or (origin_station_id if self._looks_like_gps(origin_station_id) else None)
            end_gps = destination_gps or (destination_station_id if self._looks_like_gps(destination_station_id) else None)
            if start_gps and end_gps:
                fulfillment["stops"] = [
                    {
                        "type": "START",
                        "location": {"gps": start_gps},
                    },
                    {
                        "type": "END",
                        "location": {"gps": end_gps},
                    },
                ]
            else:
                fulfillment["stops"] = [
                    {
                        "type": "START",
                        "location": {"descriptor": {"code": origin_station_id}},
                    },
                    {
                        "type": "END",
                        "location": {"descriptor": {"code": destination_station_id}},
                    },
                ]

        return {
            "intent": {
                "fulfillment": fulfillment,
                "payment": self._payment_terms(search=True),
            }
        }

    # -------------------------------------------------------------------------
    # OUTBOUND CLIENT-DRIVEN FLOWS
    # -------------------------------------------------------------------------

    async def initiate_search(
        self,
        user_id: uuid.UUID,
        origin_station_id: str,
        destination_station_id: str,
        origin_gps: Optional[str] = None,
        destination_gps: Optional[str] = None,
        city_code: str = "std:040",
        gateway_url: Optional[str] = None,
        transaction_id: Optional[uuid.UUID] = None,
    ) -> Dict[str, Any]:
        """
        1. Creates a new transaction record in DB.
        2. Constructs Beckn /search payload.
        3. Calls ONDC Gateway / BPP /search endpoint.
        """
        transaction_id = transaction_id or uuid.uuid4()
        message_id = str(uuid.uuid4())
        target_url = gateway_url or settings.ONDC_GATEWAY_URL

        # Create Transaction state
        txn = Transaction(
            transaction_id=transaction_id,
            user_id=user_id,
            city_code=city_code,
            bpp_id="pending",
            bpp_uri=target_url,
            status=OndcTxnStatus.SEARCHED,
            total_base_fare=Decimal("0.00"),
            tax_amount=Decimal("0.00"),
            rewards_discount_amount=Decimal("0.00"),
            final_user_paid_amount=Decimal("0.00")
        )
        self.db.add(txn)
        await self.db.commit()

        search_payload = {
            "context": self._context("search", transaction_id, city_code),
            "message": self._search_message(origin_station_id, destination_station_id, origin_gps, destination_gps),
        }
        message_id = search_payload["context"]["message_id"]

        try:
            await self.record_protocol_message(search_payload, direction="outbound")
            cb = get_bpp_circuit_breaker(target_url)
            await cb.call(
                beckn_client.post,
                url=target_url,
                payload=search_payload
            )
        except Exception as e:
            logger.error(f"Failed outbound /search call to {target_url}: {e}")
            txn.status = OndcTxnStatus.FAILED
            await self.db.commit()

        return {
            "transaction_id": str(transaction_id),
            "message_id": message_id,
            "status": "SEARCH_INITIATED"
        }

    async def initiate_select(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        item_id: str,
        provider_id: str = "P1",
        passenger_count: int = 1,
        reward_points_to_redeem: int = 0
    ) -> Dict[str, Any]:
        """
        1. Validates transaction state.
        2. Reserves reward points via 2PC Rewards Manager (Phase 1).
        3. Constructs and sends Beckn /select payload to BPP.
        """
        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id, Transaction.user_id == user_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if not txn:
            raise ValueError("Transaction not found")

        # Phase 1 2PC Rewards Reserve
        discount_inr = Decimal("0.00")
        if reward_points_to_redeem > 0:
            success, msg, discount_inr = await self.rewards_mgr.reserve_points(
                user_id=user_id,
                transaction_id=transaction_id,
                points_to_hold=reward_points_to_redeem
            )
            if not success:
                raise ValueError(f"Rewards reservation failed: {msg}")

        txn.rewards_discount_amount = discount_inr
        # Price the quote server-side so /confirm and Razorpay order-creation
        # have an authoritative amount to work from. When on_select later lands
        # with a real quote, the callback handler must overwrite these.
        unit_price = _catalog_price(item_id)
        txn.total_base_fare = unit_price * passenger_count
        txn.tax_amount = Decimal("0.00")
        await self.db.commit()

        select_payload = {
            "context": self._context("select", transaction_id, txn.city_code, txn.bpp_id, txn.bpp_uri),
            "message": {
                "order": {
                    "provider": {"id": provider_id},
                    "items": [
                        {
                            "id": item_id,
                            "quantity": {"selected": {"count": passenger_count}}
                        }
                    ]
                }
            }
        }

        await self.record_protocol_message(select_payload, direction="outbound")
        cb = get_bpp_circuit_breaker(txn.bpp_uri)
        await cb.call(beckn_client.post, url=f"{txn.bpp_uri}/select", payload=select_payload)

        return {
            "transaction_id": str(transaction_id),
            "message_id": select_payload["context"]["message_id"],
            "status": "SELECT_INITIATED"
        }

    async def initiate_init(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        item_id: str,
        passenger_name: str,
        passenger_phone: str,
        passenger_email: Optional[str] = None,
        passenger_count: int = 1,
        provider_id: str = "P1",
    ) -> Dict[str, Any]:
        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id, Transaction.user_id == user_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()
        if not txn:
            raise ValueError("Transaction not found")

        payload = await self._send_to_bpp(txn, "init", {
            "order": {
                "provider": {"id": provider_id},
                "items": [{"id": item_id, "quantity": {"selected": {"count": passenger_count}}}],
                "billing": {
                    "name": passenger_name,
                    "phone": passenger_phone,
                    **({"email": passenger_email} if passenger_email else {}),
                },
                "payments": [
                    {
                        "collected_by": "BAP",
                        "status": "NOT-PAID",
                        "type": "PRE-ORDER",
                        "tags": self._payment_terms()["tags"],
                    }
                ],
            }
        })
        txn.status = OndcTxnStatus.INITIATED
        await self.db.commit()
        return {"transaction_id": str(transaction_id), "status": "INIT_INITIATED", "ack": payload.get("message", {}).get("ack", {})}

    async def initiate_confirm(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        payment_txn_id: str,
        item_id: str = "I1",
        provider_id: str = "P1",
        passenger_count: int = 1,
    ) -> Dict[str, Any]:
        """
        Triggers outbound /confirm after user payment is completed.
        Amount is derived server-side from the txn quote — clients never
        declare their own price.
        """
        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id, Transaction.user_id == user_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if not txn:
            raise ValueError("Transaction not found")

        total_bpp_fare = txn.total_base_fare + txn.tax_amount
        if total_bpp_fare <= 0:
            raise ValueError("No priced quote on file for this transaction; run select/init first.")
        discount = txn.rewards_discount_amount or Decimal("0")
        net_paid = max(Decimal("1.00"), total_bpp_fare - discount)  # clamp to ₹1 like Razorpay
        txn.final_user_paid_amount = net_paid
        txn.status = OndcTxnStatus.PAID
        await self.db.commit()

        total_bpp_fare_str = str(total_bpp_fare)

        confirm_payload = {
            "context": self._context("confirm", transaction_id, txn.city_code, txn.bpp_id, txn.bpp_uri),
            "message": {
                "order": {
                    "provider": {"id": provider_id},
                    "items": [{"id": item_id, "quantity": {"selected": {"count": passenger_count}}}],
                    "payments": [
                        {
                            "id": await self._payment_id_from_on_init(transaction_id),
                            "collected_by": "BAP",
                            "status": "PAID",
                            "type": "PRE-ORDER",
                            "params": {
                                "transaction_id": payment_txn_id,
                                "amount": total_bpp_fare_str,
                                "currency": "INR",
                            },
                            "tags": self._payment_terms(total_bpp_fare_str)["tags"],
                        }
                    ],
                }
            }
        }

        await self.record_protocol_message(confirm_payload, direction="outbound")
        cb = get_bpp_circuit_breaker(txn.bpp_uri)
        await cb.call(beckn_client.post, url=f"{txn.bpp_uri}/confirm", payload=confirm_payload)

        return {
            "transaction_id": str(transaction_id),
            "message_id": confirm_payload["context"]["message_id"],
            "status": "CONFIRM_INITIATED"
        }

    async def initiate_status(self, user_id: uuid.UUID, transaction_id: uuid.UUID, order_id: Optional[str] = None) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "status", {"order_id": order_id or str(transaction_id)})
        return {"transaction_id": str(transaction_id), "status": "STATUS_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_cancel(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        order_id: Optional[str] = None,
        reason_id: str = "001",
        descriptor_code: str = "SOFT_CANCEL",
        descriptor_name: str = "Ride Cancellation",
    ) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "cancel", {
            "order_id": order_id or str(transaction_id),
            "cancellation_reason_id": reason_id,
            "descriptor": {"name": descriptor_name, "code": descriptor_code},
        })
        return {"transaction_id": str(transaction_id), "status": "CANCEL_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_support(self, user_id: uuid.UUID, transaction_id: uuid.UUID, order_id: Optional[str] = None) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "support", {"ref_id": order_id or str(transaction_id)})
        return {"transaction_id": str(transaction_id), "status": "SUPPORT_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def _get_user_txn(self, user_id: uuid.UUID, transaction_id: uuid.UUID) -> Transaction:
        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id, Transaction.user_id == user_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()
        if not txn:
            raise ValueError("Transaction not found")
        return txn

    def _safe_transaction_uuid(self, transaction_id: Optional[str]) -> Optional[uuid.UUID]:
        if not transaction_id:
            return None
        try:
            return uuid.UUID(transaction_id)
        except ValueError:
            logger.warning(f"Ignoring callback with invalid transaction_id '{transaction_id}'")
            return None

    async def initiate_update(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        order_id: Optional[str] = None,
        update_target: str = "order.fulfillments",
        payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "update", {
            "update_target": update_target,
            "order": {
                "id": order_id or str(transaction_id),
                **(payload or {}),
            },
        })
        return {"transaction_id": str(transaction_id), "status": "UPDATE_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_track(self, user_id: uuid.UUID, transaction_id: uuid.UUID, order_id: Optional[str] = None) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "track", {"order_id": order_id or str(transaction_id)})
        return {"transaction_id": str(transaction_id), "status": "TRACK_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_rating(
        self,
        user_id: uuid.UUID,
        transaction_id: uuid.UUID,
        order_id: Optional[str],
        rating_category: str,
        value: str,
        feedback: Optional[str] = None,
    ) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "rating", {
            "ratings": [
                {
                    "id": order_id or str(transaction_id),
                    "rating_category": rating_category,
                    "value": value,
                    **({"feedback": feedback} if feedback else {}),
                }
            ]
        })
        return {"transaction_id": str(transaction_id), "status": "RATING_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    def _issue_actor(self) -> Dict[str, Any]:
        return {
            "org": {"name": settings.BAP_ID},
            "contact": {},
            "person": {"name": "MetroSafar customer"},
        }

    def _issue_actions(self, issue: Issue, updated_at: str) -> Dict[str, Any]:
        open_action = {
            "complainant_action": "OPEN",
            "short_desc": issue.category,
            "updated_at": issue.created_at.isoformat() if issue.created_at else updated_at,
            "updated_by": self._issue_actor(),
        }
        complainant_actions = [open_action]
        if issue.status == IssueStatus.CLOSED:
            complainant_actions.append({
                "complainant_action": "CLOSE",
                "short_desc": issue.resolution or "Issue closed by complainant.",
                "updated_at": updated_at,
                "updated_by": self._issue_actor(),
            })

        return {
            "complainant_actions": complainant_actions,
        }

    async def initiate_issue(
        self,
        user_id: uuid.UUID,
        issue: Issue,
        transaction_id: Optional[uuid.UUID] = None,
    ) -> Dict[str, Any]:
        txn = await self._get_user_txn(user_id, transaction_id) if transaction_id else None
        if txn:
            context = self._context("issue", txn.transaction_id, txn.city_code, txn.bpp_id, txn.bpp_uri)
            target_uri = txn.bpp_uri
        else:
            context = self._context(
                "issue",
                self._safe_transaction_uuid(issue.transaction_id) or uuid.uuid4(),
                settings.ONDC_CITY_CODE,
            )
            target_uri = settings.ONDC_GATEWAY_URL.rsplit("/", 1)[0]

        updated_at = issue.updated_at.isoformat() if issue.updated_at else self._timestamp()
        issue_payload = {
            "id": str(issue.issue_id),
            "category": issue.category,
            "sub_category": self._issue_sub_category(issue.category),
            "status": issue.status.value,
            "issue_type": "ISSUE",
            "created_at": issue.created_at.isoformat() if issue.created_at else updated_at,
            "updated_at": updated_at,
            "complainant_info": {"person": {"name": "MetroSafar customer"}},
            "description": {"short_desc": issue.category, "long_desc": issue.description},
            "order_details": {
                **({"id": issue.order_id} if issue.order_id else {}),
            },
            "issue_actions": self._issue_actions(issue, updated_at),
        }
        if issue.status == IssueStatus.CLOSED:
            issue_payload["rating"] = "THUMBS-UP"
            issue_payload["resolution"] = {"short_desc": issue.resolution or "Issue resolved."}

        payload = {
            "context": context,
            "message": {
                "issue": issue_payload
            },
        }
        await self.record_protocol_message(payload, direction="outbound")
        cb = get_bpp_circuit_breaker(target_uri)
        ack = await cb.call(beckn_client.post, url=f"{target_uri.rstrip('/')}/issue", payload=payload)
        issue.status = IssueStatus.ACKNOWLEDGED
        trail = list(issue.trail or [])
        trail.append({"status": IssueStatus.ACKNOWLEDGED.value, "note": "Issue sent to ONDC counterparty", "timestamp": self._timestamp()})
        issue.trail = trail
        await self.db.commit()
        return {"issue_id": str(issue.issue_id), "status": "ISSUE_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def respond_to_issue(
        self,
        user_id: uuid.UUID,
        issue: Issue,
        action_type: str,
        note: Optional[str] = None,
        rating: Optional[str] = None,
    ) -> Dict[str, Any]:
        transaction_id = self._safe_transaction_uuid(issue.transaction_id)
        txn = await self._get_user_txn(user_id, transaction_id) if transaction_id else None
        if txn:
            context = self._context("issue", txn.transaction_id, txn.city_code, txn.bpp_id, txn.bpp_uri)
            target_uri = txn.bpp_uri
        else:
            context = self._context(
                "issue",
                transaction_id or uuid.uuid4(),
                settings.ONDC_CITY_CODE,
            )
            target_uri = settings.ONDC_GATEWAY_URL.rsplit("/", 1)[0]

        now_str = self._timestamp()
        trail = list(issue.trail or [])
        trail.append({
            "action": action_type,
            "status": issue.status.value if isinstance(issue.status, IssueStatus) else str(issue.status),
            "note": note or f"Action {action_type} performed by customer/support.",
            "timestamp": now_str
        })
        issue.trail = trail

        if action_type in {"CLOSED", "RESOLUTION_ACCEPTED"}:
            issue.status = IssueStatus.CLOSED
        elif action_type == "RESOLVED":
            issue.status = IssueStatus.RESOLVED

        complainant_actions = []
        for t in trail:
            if isinstance(t, dict) and t.get("action"):
                complainant_action = "CLOSE" if t["action"] == "CLOSED" else t["action"]
                complainant_actions.append({
                    "complainant_action": complainant_action,
                    "short_desc": t.get("note") or ("Complaint closed" if complainant_action == "CLOSE" else complainant_action),
                    "updated_at": t.get("timestamp", now_str),
                    "updated_by": self._issue_actor(),
                })
        if not complainant_actions:
            complainant_action = "CLOSE" if action_type == "CLOSED" else action_type
            complainant_actions.append({
                "complainant_action": complainant_action,
                "short_desc": note or ("Complaint closed" if complainant_action == "CLOSE" else complainant_action),
                "updated_at": now_str,
                "updated_by": self._issue_actor(),
            })

        issue_payload = {
            "id": str(issue.issue_id),
            "status": issue.status.value if isinstance(issue.status, IssueStatus) else str(issue.status),
            "created_at": issue.created_at.isoformat() if issue.created_at else now_str,
            "updated_at": now_str,
            "issue_actions": {
                "complainant_actions": complainant_actions,
            }
        }
        if rating or issue.status == IssueStatus.CLOSED:
            issue_payload["rating"] = rating or "THUMBS-UP"

        payload = {
            "context": context,
            "message": {"issue": issue_payload}
        }
        await self.record_protocol_message(payload, direction="outbound")
        cb = get_bpp_circuit_breaker(target_uri)
        ack = await cb.call(beckn_client.post, url=f"{target_uri.rstrip('/')}/issue", payload=payload)

        await self.db.commit()
        await self.db.refresh(issue)
        return {
            "issue_id": str(issue.issue_id),
            "status": issue.status.value if isinstance(issue.status, IssueStatus) else str(issue.status),
            "action_type": action_type,
            "ack": ack.get("message", {}).get("ack", {})
        }

    async def initiate_issue_status(self, user_id: uuid.UUID, issue: Issue) -> Dict[str, Any]:
        transaction_id = self._safe_transaction_uuid(issue.transaction_id)
        if not transaction_id:
            raise ValueError("Issue is not linked to a valid transaction_id")
        txn = await self._get_user_txn(user_id, transaction_id)
        ack = await self._send_to_bpp(txn, "issue_status", {"issue_id": str(issue.issue_id)})
        return {"issue_id": str(issue.issue_id), "status": "ISSUE_STATUS_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_receiver_recon(self, recon: ReconRecord) -> Dict[str, Any]:
        transaction_id = self._safe_transaction_uuid(recon.transaction_id) or uuid.uuid4()
        payload = {
            "context": self._context("receiver_recon", transaction_id, settings.ONDC_CITY_CODE),
            "message": {
                "orderbook": {
                    "orders": [
                        {
                            "id": recon.order_id or recon.transaction_id,
                            "transaction_id": recon.transaction_id,
                            "payment_id": recon.payment_txn_id,
                            "collector": settings.BAP_ID,
                            "receiver": recon.settlement_party,
                            "withholding_amount": {"currency": "INR", "value": str(recon.buyer_finder_fee or 0)},
                            "settlement_amount": {"currency": "INR", "value": str(recon.settlement_amount or 0)},
                            "refund_amount": {"currency": "INR", "value": str(recon.refund_adjustment or 0)},
                            "status": recon.status.value,
                        }
                    ]
                }
            },
        }
        target_url = settings.ONDC_GATEWAY_URL.rsplit("/", 1)[0]
        await self.record_protocol_message(payload, direction="outbound")
        cb = get_bpp_circuit_breaker(target_url)
        ack = await cb.call(beckn_client.post, url=f"{target_url.rstrip('/')}/receiver_recon", payload=payload)
        return {"recon_id": str(recon.recon_id), "status": "RECEIVER_RECON_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    async def initiate_settle(self, payout: PayoutRecord) -> Dict[str, Any]:
        transaction_id = self._safe_transaction_uuid(payout.transaction_id) or uuid.uuid4()
        payload = {
            "context": self._context("settle", transaction_id, settings.ONDC_CITY_CODE),
            "message": {
                "settlement": {
                    "id": str(payout.payout_id),
                    "orders": [
                        {
                            "id": payout.order_id or payout.transaction_id,
                            "transaction_id": payout.transaction_id,
                            "amount": {"currency": payout.currency, "value": str(payout.amount or 0)},
                            "settlement_party": payout.settlement_party,
                            "settlement_reference": payout.payout_reference,
                            "status": payout.status.value,
                        }
                    ]
                }
            },
        }
        target_url = settings.ONDC_GATEWAY_URL.rsplit("/", 1)[0]
        await self.record_protocol_message(payload, direction="outbound")
        cb = get_bpp_circuit_breaker(target_url)
        ack = await cb.call(beckn_client.post, url=f"{target_url.rstrip('/')}/settle", payload=payload)
        payout.status = PayoutStatus.INITIATED
        await self.db.commit()
        return {"payout_id": str(payout.payout_id), "status": "SETTLE_INITIATED", "ack": ack.get("message", {}).get("ack", {})}

    # -------------------------------------------------------------------------
    # INBOUND WEBHOOK CALLBACK HANDLERS (BPP -> BNP)
    # -------------------------------------------------------------------------

    async def handle_on_search(self, payload: Dict[str, Any]):
        context = payload.get("context", {})
        transaction_id_str = context.get("transaction_id")
        bpp_id = context.get("bpp_id", "")
        bpp_uri = context.get("bpp_uri", "")

        if not transaction_id_str:
            return

        transaction_id = self._safe_transaction_uuid(transaction_id_str)
        if not transaction_id:
            return

        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if txn:
            txn.bpp_id = bpp_id
            txn.bpp_uri = bpp_uri
            txn.status = OndcTxnStatus.SEARCHED
            await self.db.commit()

        await self.sse_mgr.publish_event(transaction_id_str, "on_search", payload)

    async def handle_on_select(self, payload: Dict[str, Any]):
        context = payload.get("context", {})
        transaction_id_str = context.get("transaction_id")
        message = payload.get("message", {})
        quote = message.get("order", {}).get("quote", {})
        price_obj = quote.get("price", {})

        if not transaction_id_str:
            return

        transaction_id = self._safe_transaction_uuid(transaction_id_str)
        if not transaction_id:
            return

        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if txn:
            total_price = Decimal(price_obj.get("value", "0.00"))
            txn.total_base_fare = total_price
            txn.status = OndcTxnStatus.SELECTED
            await self.db.commit()

        await self.sse_mgr.publish_event(transaction_id_str, "on_select", payload)

    async def handle_on_init(self, payload: Dict[str, Any]):
        context = payload.get("context", {})
        transaction_id_str = context.get("transaction_id")

        if not transaction_id_str:
            return

        transaction_id = self._safe_transaction_uuid(transaction_id_str)
        if not transaction_id:
            return

        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if txn:
            txn.status = OndcTxnStatus.INITIATED
            await self.db.commit()

        await self.sse_mgr.publish_event(transaction_id_str, "on_init", payload)

    async def handle_on_confirm(self, payload: Dict[str, Any]):
        """
        Handles ticket issuance from Metro Seller (BPP).
        Extracts QR Payload, creates Ticket record, commits 2PC reward points.
        """
        context = payload.get("context", {})
        transaction_id_str = context.get("transaction_id")
        order = payload.get("message", {}).get("order", {})
        fulfillments = order.get("fulfillments", [])

        if not transaction_id_str or not fulfillments:
            return

        transaction_id = self._safe_transaction_uuid(transaction_id_str)
        if not transaction_id:
            return

        stmt = select(Transaction).where(Transaction.transaction_id == transaction_id)
        result = await self.db.execute(stmt)
        txn = result.scalar_one_or_none()

        if not txn:
            return

        # Extract Encrypted QR payload or fulfillment token
        fulfillment = fulfillments[0]
        qr_code_str = ""
        tokens = fulfillment.get("tokens", [])
        if tokens and len(tokens) > 0:
            qr_code_str = tokens[0].get("token", "")
        else:
            qr_code_str = json.dumps(fulfillment)

        # Parse Stops
        stops = fulfillment.get("stops", [])
        origin_id = stops[0].get("location", {}).get("id", "UNKNOWN") if len(stops) > 0 else "ORIGIN"
        dest_id = stops[-1].get("location", {}).get("id", "UNKNOWN") if len(stops) > 1 else "DEST"

        now = datetime.datetime.now(datetime.timezone.utc)
        valid_until = now + datetime.timedelta(hours=24)  # Metro ticket default 24h validity

        # Create Ticket Record
        ticket = Ticket(
            ticket_id=uuid.uuid4(),
            transaction_id=transaction_id,
            user_id=txn.user_id,
            metro_operator_id=txn.bpp_id,
            origin_station_id=origin_id,
            destination_station_id=dest_id,
            passenger_count=1,
            qr_payload=qr_code_str,
            valid_from=now,
            valid_until=valid_until,
            status=TicketStatus.ISSUED
        )
        self.db.add(ticket)

        txn.status = OndcTxnStatus.CONFIRMED
        await self.db.commit()

        # Phase 2 2PC Rewards Commit
        await self.rewards_mgr.commit_points(user_id=txn.user_id, transaction_id=transaction_id)

        # Stream update via SSE
        await self.sse_mgr.publish_event(transaction_id_str, "on_confirm", payload)

    async def handle_generic_callback(self, action: str, payload: Dict[str, Any]):
        context = payload.get("context", {})
        transaction_id_str = context.get("transaction_id")
        if transaction_id_str:
            await self.sse_mgr.publish_event(transaction_id_str, action, payload)

        if action == "on_status" and transaction_id_str:
            try:
                transaction_id = self._safe_transaction_uuid(transaction_id_str)
                if not transaction_id:
                    return
                stmt = select(Transaction).where(Transaction.transaction_id == transaction_id)
                result = await self.db.execute(stmt)
                txn = result.scalar_one_or_none()
                if txn:
                    order_state = payload.get("message", {}).get("order", {}).get("state")
                    if order_state == "CANCELLED":
                        txn.status = OndcTxnStatus.CANCELLED
                    await self.db.commit()
            except Exception as exc:
                logger.warning(f"Unable to update status callback for {transaction_id_str}: {exc}")

        if action in {"on_issue", "on_issue_status"}:
            await self._handle_issue_callback(action, payload)
        elif action == "on_receiver_recon":
            await self._handle_receiver_recon_callback(payload)
        elif action == "on_settle":
            await self._handle_settle_callback(payload)

    async def _handle_issue_callback(self, action: str, payload: Dict[str, Any]) -> None:
        issue_payload = payload.get("message", {}).get("issue", {})
        issue_id = issue_payload.get("id") or issue_payload.get("issue_id")
        if not issue_id:
            return
        try:
            parsed_id = uuid.UUID(issue_id)
        except ValueError:
            logger.warning(f"Ignoring {action} with invalid issue id '{issue_id}'")
            return

        result = await self.db.execute(select(Issue).where(Issue.issue_id == parsed_id))
        issue = result.scalar_one_or_none()
        if not issue:
            category_val = issue_payload.get("category", "FULFILLMENT")
            status_val = issue_payload.get("status", "OPEN")
            status_enum = IssueStatus(status_val) if status_val in IssueStatus._value2member_map_ else IssueStatus.OPEN
            desc_dict = issue_payload.get("description", {})
            desc_str = desc_dict.get("long_desc") or desc_dict.get("short_desc") if isinstance(desc_dict, dict) else str(desc_dict or "ONDC IGM Issue")
            issue = Issue(
                issue_id=parsed_id,
                user_id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
                order_id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
                category=category_val,
                sub_category=issue_payload.get("sub_category", "FLM101"),
                issue_type=issue_payload.get("issue_type", "ISSUE"),
                status=status_enum,
                description=desc_str,
                resolution=json.dumps(issue_payload.get("resolution")) if issue_payload.get("resolution") else None,
                trail=[],
            )
            self.db.add(issue)

        status_value = issue_payload.get("status")
        if status_value in IssueStatus._value2member_map_:
            issue.status = IssueStatus(status_value)
        resolution = issue_payload.get("resolution") or issue_payload.get("resolution_provider")
        if resolution:
            issue.resolution = json.dumps(resolution) if isinstance(resolution, dict) else str(resolution)
        trail = list(issue.trail or [])
        trail.append({
            "status": issue.status.value,
            "note": f"Received {action}",
            "timestamp": self._timestamp(),
            "payload": issue_payload,
        })
        issue.trail = trail
        await self.db.commit()

    async def _handle_receiver_recon_callback(self, payload: Dict[str, Any]) -> None:
        orders = payload.get("message", {}).get("orderbook", {}).get("orders", [])
        for order in orders:
            recon = ReconRecord(
                transaction_id=order.get("transaction_id"),
                order_id=order.get("id"),
                payment_txn_id=order.get("payment_id"),
                buyer_finder_fee=Decimal(str(order.get("withholding_amount", {}).get("value", "0.00"))),
                settlement_party=order.get("receiver"),
                settlement_amount=Decimal(str(order.get("settlement_amount", {}).get("value", "0.00"))),
                refund_adjustment=Decimal(str(order.get("refund_amount", {}).get("value", "0.00"))),
                status=ReconStatus.RECONCILED,
                details={"source": "on_receiver_recon", "payload": order},
            )
            self.db.add(recon)
        await self.db.commit()

    async def _handle_settle_callback(self, payload: Dict[str, Any]) -> None:
        orders = payload.get("message", {}).get("settlement", {}).get("orders", [])
        for order in orders:
            payout = PayoutRecord(
                transaction_id=order.get("transaction_id"),
                order_id=order.get("id"),
                settlement_party=order.get("settlement_party"),
                amount=Decimal(str(order.get("amount", {}).get("value", "0.00"))),
                currency=order.get("amount", {}).get("currency", "INR"),
                payout_reference=order.get("settlement_reference"),
                status=PayoutStatus.PAID if order.get("status") in {"PAID", "SETTLED"} else PayoutStatus.INITIATED,
                details={"source": "on_settle", "payload": order},
            )
            self.db.add(payout)
        await self.db.commit()
