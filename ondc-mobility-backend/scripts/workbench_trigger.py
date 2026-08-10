#!/usr/bin/env python3
"""
Send signed ONDC TRV11 BAP requests to ONDC Workbench.

This is intentionally stateless: it can continue a Workbench flow by reusing the
transaction_id shown in the Workbench Request tab even if the Cloud Run test DB
has restarted between steps.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from nacl.signing import SigningKey


DEFAULT_KEY_FILE = Path.home() / ".metrosafar" / "ondc" / "preprod" / "keys.json"
DEFAULT_WORKBENCH_BASE = "https://workbench.ondc.tech/api-service/ONDC:TRV11/2.0.0/seller"


def now_iso() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def payment_tags(static_terms_url: str, amount: str | None = None, *, search: bool = False) -> list[dict[str, Any]]:
    settlement_terms = [
        {"descriptor": {"code": "DELAY_INTEREST"}, "value": "2.5"},
        {"descriptor": {"code": "STATIC_TERMS"}, "value": static_terms_url},
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
    if amount and not search:
        settlement_terms.insert(0, {"descriptor": {"code": "SETTLEMENT_AMOUNT"}, "value": amount})

    return [
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
    ]


def digest(body: bytes) -> str:
    return "BLAKE-512=" + base64.b64encode(hashlib.blake2b(body, digest_size=64).digest()).decode()


def signing_key(private_key_b64: str) -> SigningKey:
    raw = base64.b64decode(private_key_b64)
    if len(raw) < 32:
        raise ValueError(f"Signing key is too short: {len(raw)} bytes")
    return SigningKey(raw[:32])


def auth_headers(body: bytes, subscriber_id: str, unique_key_id: str, private_key_b64: str) -> dict[str, str]:
    created = int(time.time())
    expires = created + 300
    body_digest = digest(body)
    signing_string = f"(created): {created}\n(expires): {expires}\ndigest: {body_digest}"
    signature = signing_key(private_key_b64).sign(signing_string.encode()).signature
    return {
        "Content-Type": "application/json",
        "Digest": body_digest,
        "Authorization": (
            f'Signature keyId="{subscriber_id}|{unique_key_id}|ed25519",'
            f'algorithm="ed25519",'
            f'created="{created}",'
            f'expires="{expires}",'
            f'headers="(created) (expires) digest",'
            f'signature="{base64.b64encode(signature).decode()}"'
        ),
    }


def context(args: argparse.Namespace, action: str) -> dict[str, Any]:
    msg_id = getattr(args, "message_id", None) or str(uuid.uuid4())
    wb_base = getattr(args, "workbench_base", DEFAULT_WORKBENCH_BASE)
    wb_base_clean = wb_base.replace("//seller", "/seller")
    ctx = {
        "domain": args.domain.strip("/"),
        "location": {
            "country": {"code": args.country_code},
            "city": {"code": args.city_code},
        },
        "action": action,
        "version": args.version.strip("/"),
        "bap_id": args.subscriber_id,
        "bap_uri": args.subscriber_uri,
        "transaction_id": args.transaction_id,
        "message_id": msg_id,
        "timestamp": now_iso(),
        "ttl": "PT30S",
    }
    if action != "search" or args.include_bpp_in_search:
        ctx["bpp_id"] = args.bpp_id
        ctx["bpp_uri"] = wb_base_clean
    return ctx


def search_message(args: argparse.Namespace) -> dict[str, Any]:
    fulfillment: dict[str, Any] = {"vehicle": {"category": "METRO"}}
    if not args.catalog:
        fulfillment["stops"] = [
            {"type": "START", "location": {"descriptor": {"code": args.origin}}},
            {"type": "END", "location": {"descriptor": {"code": args.destination}}},
        ]
    return {
        "intent": {
            "fulfillment": fulfillment,
            "payment": {
                "collected_by": "BAP",
                "tags": payment_tags(args.static_terms_url, search=True),
            },
        }
    }


def order_items(args: argparse.Namespace) -> list[dict[str, Any]]:
    return [
        {
            "id": args.item_id,
            "quantity": {"selected": {"count": args.passenger_count}},
        }
    ]


def billing(args: argparse.Namespace) -> dict[str, str]:
    return {
        "name": args.passenger_name,
        "email": args.passenger_email,
        "phone": args.passenger_phone,
    }


def issue_actor(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "org": {"name": f"{args.subscriber_id}::{args.domain}"},
        "contact": {
            "phone": args.passenger_phone,
            "email": args.passenger_email,
        },
        "person": {"name": args.passenger_name},
    }


def complainant_action(args: argparse.Namespace, action: str, short_desc: str) -> dict[str, Any]:
    return {
        "complainant_action": action,
        "short_desc": short_desc,
        "updated_at": now_iso(),
        "updated_by": issue_actor(args),
    }


def build_message(args: argparse.Namespace, action: str) -> dict[str, Any]:
    if action == "search":
        return search_message(args)
    if action == "select":
        return {"order": {"provider": {"id": args.provider_id}, "items": order_items(args)}}
    if action == "init":
        return {
            "order": {
                "provider": {"id": args.provider_id},
                "items": order_items(args),
                "billing": billing(args),
                "payments": [
                    {
                        "collected_by": "BAP",
                        "status": "NOT-PAID",
                        "type": "PRE-ORDER",
                        "tags": payment_tags(args.static_terms_url, args.amount),
                    }
                ],
            }
        }
    if action == "confirm":
        return {
            "order": {
                "provider": {"id": args.provider_id},
                "items": order_items(args),
                "billing": billing(args),
                "payments": [
                    {
                        "id": "PA1",
                        "collected_by": "BAP",
                        "status": "PAID",
                        "type": "PRE-ORDER",
                        "params": {
                            "transaction_id": args.payment_txn_id or f"pay-{uuid.uuid4()}",
                            "currency": "INR",
                            "amount": args.amount,
                            "bank_code": "XXXXXXXX",
                            "bank_account_number": "xxxxxxxxxxxxxx",
                        },
                        "tags": payment_tags(args.static_terms_url, args.amount),
                    }
                ],
            }
        }
    if action == "status":
        action_id = getattr(args, "action_id", "").lower()
        if "tech_cancel" in action_id or "cancel" in action_id:
            return {"ref_id": args.order_id}
        return {"order_id": args.order_id}
    if action == "cancel":
        return {
            "order_id": args.order_id,
            "cancellation_reason_id": args.reason_id,
            "descriptor": {"name": args.cancel_name, "code": args.cancel_code},
        }
    if action == "update":
        action_id = getattr(args, "action_id", "")
        action_id_lower = action_id.lower()
        order: dict[str, Any] = {"id": args.order_id}
        update_target = args.update_target

        if "end_stop" in action_id_lower:
            step_num = 1
            for n in (3, 2, 1):
                if action_id.endswith(f"_{n}"):
                    step_num = n
                    break
            if step_num == 3:
                update_target = "payments"
                order["payments"] = [
                    {
                        "id": "PA2",
                        "collected_by": "BAP",
                        "status": "PAID",
                        "type": "POST-FULFILLMENT",
                        "params": {
                            "transaction_id": args.payment_txn_id or f"pay-{uuid.uuid4()}",
                            "amount": args.amount,
                            "currency": "INR",
                        },
                    }
                ]
            else:
                update_target = "order.fulfillments"
                order["status"] = "SOFT_UPDATE" if step_num == 1 else "CONFIRM_UPDATE"
                order["fulfillments"] = [
                    {
                        "id": args.fulfillment_id,
                        "stops": [
                            {
                                "type": "END",
                                "location": {
                                    "descriptor": {
                                        "name": args.update_end_code.replace("_", " ").title(),
                                        "code": args.update_end_code,
                                    },
                                    "gps": "28.707358, 77.180910",
                                },
                            }
                        ],
                    }
                ]
        elif "partial_cancellation" in action_id_lower:
            update_target = "order.fulfillments"
            step_num = 2 if action_id.endswith("_2") else 1
            cancel_code = "SOFT_CANCEL" if step_num == 1 else "CONFIRM_CANCEL"
            order["fulfillments"] = [
                {
                    "id": args.fulfillment_id,
                    "type": "TICKET",
                }
            ]
            order["cancellation"] = {
                "reason": {
                    "id": args.reason_id or "001",
                    "descriptor": {"code": cancel_code},
                }
            }
        elif update_target == "order.fulfillments":
            order["cancellation"] = {
                "cancelled_by": "CONSUMER",
                "reason": {
                    "id": args.reason_id or "001",
                    "descriptor": {
                        "code": args.cancel_code,
                        "name": args.cancel_name,
                    },
                },
            }
            order["fulfillments"] = [
                {
                    "id": args.fulfillment_id,
                    "type": "TRIP",
                }
            ]
        else:
            order.update(
                {
                    "provider": {"id": args.provider_id},
                    "items": [
                        {
                            "id": args.item_id,
                            "quantity": {"selected": {"count": args.update_count}},
                        }
                    ],
                }
            )
        return {"update_target": update_target, "order": order}
    if action == "support":
        return {"ref_id": args.transaction_id}
    if action == "issue":
        issue_action = args.issue_action or (
            "CLOSE" if args.issue_status.upper() == "CLOSED" else "OPEN"
        )
        action_desc = args.issue_resolution if issue_action == "CLOSE" else args.issue_short_desc

        new_comp_act = complainant_action(args, issue_action, action_desc)
        comp_actions = list(getattr(args, "past_complainant_actions", []) or [])
        if not any(ca.get("complainant_action") == issue_action for ca in comp_actions):
            comp_actions.append(new_comp_act)

        resp_actions = list(getattr(args, "past_respondent_actions", []) or [])
        issue_actions = {
            "complainant_actions": comp_actions,
            "respondent_actions": resp_actions,
        }
        created_at = args.issue_created_at or now_iso()
        issue: dict[str, Any] = {
            "id": args.issue_id,
            "category": args.issue_category,
            "status": args.issue_status,
            "created_at": created_at,
            "updated_at": now_iso(),
            "complainant_info": {
                "person": {"name": args.passenger_name},
                "contact": {
                    "phone": args.passenger_phone,
                    "email": args.passenger_email,
                },
            },
            "description": {
                "short_desc": args.issue_short_desc,
                "long_desc": args.issue_long_desc,
                "additional_desc": {"url": ""},
                "images": [],
            },
            "order_details": {
                "id": args.order_id,
                "state": "COMPLETED",
                "provider_id": args.provider_id,
                "items": [
                    {
                        "id": args.item_id,
                        "quantity": args.passenger_count,
                    }
                ],
                "fulfillments": [
                    {
                        "id": args.fulfillment_id,
                        "state": "COMPLETED",
                    }
                ],
            },
            "source": {
                "network_participant_id": args.subscriber_id,
                "type": "CONSUMER",
            },
            "expected_response_time": {
                "duration": args.issue_expected_response_time,
            },
            "expected_resolution_time": {
                "duration": args.issue_expected_resolution_time,
            },
            "issue_actions": issue_actions,
        }
        if "1.0.0" not in getattr(args, "flow_id", "") and str(args.version) != "1.0.0":
            issue["sub_category"] = args.issue_sub_category
            issue["issue_type"] = args.issue_type

        if args.issue_status.upper() == "CLOSED":
            issue["rating"] = args.rating
            issue["resolution"] = {
                "short_desc": args.issue_resolution,
            }
        return {"issue": issue}
    raise ValueError(f"Unsupported action: {action}")


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    return {"context": context(args, args.action), "message": build_message(args, args.action)}


def load_private_key(path: Path) -> str:
    data = json.loads(path.read_text())
    private_key = data.get("signing_private_key")
    if not private_key:
        raise ValueError(f"No signing_private_key found in {path}")
    return private_key


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Trigger a signed ONDC Workbench TRV11 action.")
    parser.add_argument("action", choices=["search", "select", "init", "confirm", "status", "cancel", "update", "support", "issue"])
    parser.add_argument("--transaction-id", default=str(uuid.uuid4()))
    parser.add_argument("--catalog", action="store_true", help="Send station-code catalog search without start/end stops.")
    parser.add_argument("--workbench-base", default=DEFAULT_WORKBENCH_BASE)
    parser.add_argument("--bpp-id", default="workbench.ondc.tech")
    parser.add_argument("--omit-bpp-in-search", dest="include_bpp_in_search", action="store_false")
    parser.set_defaults(include_bpp_in_search=True)
    parser.add_argument("--subscriber-id", default="ondc.metrosafar.in")
    parser.add_argument("--subscriber-uri", default="https://ondc.metrosafar.in/ondc")
    parser.add_argument("--unique-key-id", default="d6acb12b-6334-4a01-8825-e5f1b60f01f5")
    parser.add_argument("--key-file", type=Path, default=DEFAULT_KEY_FILE)
    parser.add_argument("--domain", default="ONDC:TRV11")
    parser.add_argument("--version", default="2.0.0")
    parser.add_argument("--country-code", default="IND")
    parser.add_argument("--city-code", default="std:040")
    parser.add_argument("--origin", default="MOCK_STATION_1")
    parser.add_argument("--destination", default="MOCK_STATION_2")
    parser.add_argument("--provider-id", default="P1")
    parser.add_argument("--item-id", default="I1")
    parser.add_argument("--passenger-count", type=int, default=1)
    parser.add_argument("--passenger-name", default="MetroSafar Test User")
    parser.add_argument("--passenger-phone", default="+91-9999999999")
    parser.add_argument("--passenger-email", default="test@metrosafar.in")
    parser.add_argument("--amount", default="60")
    parser.add_argument("--payment-txn-id", default=None)
    parser.add_argument("--order-id", default="077b248f")
    parser.add_argument("--reason-id", default="0")
    parser.add_argument("--cancel-code", default="SOFT_CANCEL")
    parser.add_argument("--cancel-name", default="Ride Cancellation")
    parser.add_argument("--update-target", default="order.fulfillments")
    parser.add_argument("--update-count", type=int, default=1)
    parser.add_argument("--update-end-code", default="MOCK_STATION_5")
    parser.add_argument("--fulfillment-id", default="F1")
    parser.add_argument("--fulfillment-state", default="CANCELLED")
    parser.add_argument("--static-terms-url", default="https://ondc.metrosafar.in/terms")
    parser.add_argument("--issue-id", default=None)
    parser.add_argument("--issue-status", default="OPEN")
    parser.add_argument("--issue-category", default="FULFILMENT")
    parser.add_argument("--issue-sub-category", default="FLM01")
    parser.add_argument("--issue-type", default="ISSUE")
    parser.add_argument("--issue-action", default=None)
    parser.add_argument("--issue-short-desc", default="Ticket journey support")
    parser.add_argument("--issue-long-desc", default="Passenger needs assistance with the metro ticket journey.")
    parser.add_argument("--issue-resolution", default="Issue resolved by seller.")
    parser.add_argument("--issue-expected-response-time", default="PT2H")
    parser.add_argument("--issue-expected-resolution-time", default="P1D")
    parser.add_argument("--issue-created-at", default=None)
    parser.add_argument("--rating", default="THUMBS_UP")
    parser.add_argument("--print-only", action="store_true")
    args = parser.parse_args()
    if args.issue_id is None:
        args.issue_id = str(uuid.uuid4())
    return args


def main() -> int:
    args = parse_args()
    payload = build_payload(args)
    body = json.dumps(payload, separators=(",", ":")).encode()
    url = f"{args.workbench_base.rstrip('/')}/{args.action}"

    print(f"action={args.action}")
    print(f"transaction_id={args.transaction_id}")
    print(f"message_id={payload['context']['message_id']}")
    print(f"url={url}")

    if args.print_only:
        print(json.dumps(payload, indent=2))
        return 0

    private_key = load_private_key(args.key_file)
    headers = auth_headers(body, args.subscriber_id, args.unique_key_id, private_key)
    with httpx.Client(timeout=15.0) as client:
        response = client.post(url, content=body, headers=headers)

    print(f"http_status={response.status_code}")
    try:
        print(json.dumps(response.json(), indent=2))
    except Exception:
        print(response.text)
    return 0 if response.status_code < 400 else 1


if __name__ == "__main__":
    sys.exit(main())
