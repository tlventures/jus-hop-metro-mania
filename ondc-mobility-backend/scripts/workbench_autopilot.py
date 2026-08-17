#!/usr/bin/env python3
"""
Drive ONDC Workbench Buyer-side flows with signed MetroSafar BAP requests.

The script is intentionally local/admin-only. It does not expose a public endpoint
that could be abused to send signed ONDC protocol calls.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from copy import copy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

import workbench_trigger


CALLBACK_FOR_ACTION = {
    "search": "on_search",
    "select": "on_select",
    "init": "on_init",
    "confirm": "on_confirm",
    "status": "on_status",
    "cancel": "on_cancel",
    "update": "on_update",
    "support": "on_support",
    "issue": "on_issue",
}

FLOW_STEPS = {
    "catalog": ["search:catalog"],
    "station-code-catalog": ["search:catalog"],
    "sjt-wo-search-select": ["search", "init", "confirm", "status"],
    "rjt-wo-search-select": ["search", "init", "confirm", "status"],
    "sjt": ["search:discovery", "search:direct", "select", "init", "confirm", "status"],
    "rjt": ["search:discovery", "search:direct", "select", "init", "confirm", "status"],
    "user-cancellation-wo-search-select": ["search", "init", "confirm", "cancel", "status"],
    "technical-cancellation-wo-search-select": ["search", "init", "confirm", "cancel", "status"],
    "partial-cancellation": ["search:discovery", "search:direct", "select", "init", "confirm", "update", "update"],
    "partial-cancellation-wo-search-select": ["search", "init", "confirm", "update", "update"],
    "igm-sjt-wo-search-select": ["search", "init", "confirm", "status", "issue", "issue:closed"],
}
TICKET_CODE_FALLBACKS = {
    "SJT": {"item_id": "I1", "amount": "60"},
    "RJT": {"item_id": "I2", "amount": "110"},
}


@dataclass(frozen=True)
class Step:
    action: str
    variant: str | None = None

    @property
    def label(self) -> str:
        return f"{self.action}:{self.variant}" if self.variant else self.action


def parse_step(raw: str) -> Step:
    action, _, variant = raw.partition(":")
    action = action.strip()
    variant = variant.strip() or None
    if action not in CALLBACK_FOR_ACTION:
        raise ValueError(f"Unsupported action '{raw}'")
    return Step(action=action, variant=variant)


def flow_steps(args: argparse.Namespace) -> list[Step]:
    if args.actions:
        return [parse_step(item) for item in args.actions.split(",") if item.strip()]
    return [parse_step(item) for item in FLOW_STEPS[args.flow]]


def trigger_args(base_args: argparse.Namespace, step: Step) -> argparse.Namespace:
    args = copy(base_args)
    args.action = step.action
    args.catalog = step.variant in {"catalog", "discovery"}
    if step.action == "search" and step.variant in {"catalog", "discovery"}:
        args.include_bpp_in_search = False
    elif step.action == "search" and step.variant == "direct":
        args.include_bpp_in_search = True
    if step.action == "issue":
        args.issue_status = "CLOSED" if step.variant == "closed" else "OPEN"
    if step.action in {"select", "init", "confirm", "update"}:
        apply_flow_ticket_default(args)
    return args


def send_signed_request(args: argparse.Namespace, step: Step) -> tuple[dict[str, Any], httpx.Response]:
    step_args = trigger_args(args, step)
    payload = workbench_trigger.build_payload(step_args)
    body = json.dumps(payload, separators=(",", ":")).encode()
    private_key = workbench_trigger.load_private_key(step_args.key_file)
    headers = workbench_trigger.auth_headers(
        body,
        step_args.subscriber_id,
        step_args.unique_key_id,
        private_key,
    )
    url = f"{step_args.workbench_base.rstrip('/')}/{step.action}"
    with httpx.Client(timeout=step_args.request_timeout) as client:
        response = client.post(url, content=body, headers=headers)
    return payload, response


def workbench_412(response: httpx.Response) -> bool:
    try:
        data = response.json()
    except Exception:
        return False
    return str(data.get("error", {}).get("code")) == "412"


def ack_status(response: httpx.Response) -> str | None:
    try:
        return response.json().get("message", {}).get("ack", {}).get("status")
    except Exception:
        return None


def observability_events(client: httpx.Client, base_url: str) -> list[dict[str, Any]]:
    response = client.get(f"{base_url.rstrip('/')}/api/v1/observability")
    response.raise_for_status()
    data = response.json()
    return data if isinstance(data, list) else []


def event_payload(event: dict[str, Any]) -> dict[str, Any]:
    payload = event.get("payload")
    return payload if isinstance(payload, dict) else {}


def ticket_code_for_flow(flow: str) -> str | None:
    flow_upper = flow.upper()
    if "RJT" in flow_upper or "RETURN" in flow_upper or "ROUND" in flow_upper:
        return "RJT"
    if "SJT" in flow_upper or "SINGLE" in flow_upper:
        return "SJT"
    return None


def item_ticket_code(item: dict[str, Any]) -> str | None:
    descriptor = item.get("descriptor") if isinstance(item.get("descriptor"), dict) else {}
    code = str(descriptor.get("code") or "").upper()
    if code in TICKET_CODE_FALLBACKS:
        return code
    name = str(descriptor.get("name") or "").upper()
    if "RETURN" in name or "ROUND" in name:
        return "RJT"
    if "SINGLE" in name:
        return "SJT"
    return None


def apply_flow_ticket_default(args: argparse.Namespace) -> None:
    ticket_code = ticket_code_for_flow(getattr(args, "flow", ""))
    if not ticket_code:
        return
    fallback = TICKET_CODE_FALLBACKS[ticket_code]
    args.item_id = fallback["item_id"]
    args.amount = fallback["amount"]


def apply_catalog_ticket_selection(args: argparse.Namespace, providers: list[dict[str, Any]]) -> bool:
    ticket_code = ticket_code_for_flow(getattr(args, "flow", ""))
    if not ticket_code:
        return False
    for provider in providers:
        if not isinstance(provider, dict):
            continue
        provider_items = provider.get("items", [])
        if not isinstance(provider_items, list):
            continue
        for item in provider_items:
            if not isinstance(item, dict) or item_ticket_code(item) != ticket_code:
                continue
            if item.get("id"):
                args.item_id = item["id"]
            if provider.get("id"):
                args.provider_id = provider["id"]
            price = item.get("price") if isinstance(item.get("price"), dict) else {}
            if price.get("value") is not None:
                args.amount = str(price["value"])
            return True
    return False


def matches_callback(event: dict[str, Any], transaction_id: str, callback_action: str) -> bool:
    payload = event_payload(event)
    return (
        (event.get("transaction_id") == transaction_id or payload.get("transaction_id") == transaction_id)
        and (event.get("action") == callback_action or payload.get("action") == callback_action)
    )


def learn_identifiers(args: argparse.Namespace, event: dict[str, Any]) -> None:
    payload = event_payload(event)
    message_payload = payload.get("payload") if isinstance(payload.get("payload"), dict) else payload
    message = message_payload.get("message", {}) if isinstance(message_payload, dict) else {}
    order = message.get("order", {}) if isinstance(message, dict) else {}
    catalog = message.get("catalog", {}) if isinstance(message, dict) else {}

    order_id = order.get("id") if isinstance(order, dict) else None
    if order_id:
        args.order_id = order_id

    provider = order.get("provider", {}) if isinstance(order, dict) else {}
    provider_id = provider.get("id") if isinstance(provider, dict) else None
    if provider_id:
        args.provider_id = provider_id

    items = order.get("items", []) if isinstance(order, dict) else []
    if isinstance(items, list) and items and isinstance(items[0], dict) and items[0].get("id"):
        args.item_id = items[0]["id"]
        price = items[0].get("price") if isinstance(items[0].get("price"), dict) else {}
        if price.get("value") is not None:
            args.amount = str(price["value"])

    providers = catalog.get("bpp_providers", []) if isinstance(catalog, dict) else []
    if isinstance(providers, list) and providers and isinstance(providers[0], dict):
        if apply_catalog_ticket_selection(args, providers):
            return
        args.provider_id = providers[0].get("id") or args.provider_id
        provider_items = providers[0].get("items", [])
        if isinstance(provider_items, list) and provider_items and isinstance(provider_items[0], dict):
            args.item_id = provider_items[0].get("id") or args.item_id


def wait_for_callback(args: argparse.Namespace, callback_action: str) -> dict[str, Any] | None:
    deadline = time.time() + args.callback_timeout
    with httpx.Client(timeout=args.request_timeout) as client:
        while time.time() < deadline:
            try:
                for event in observability_events(client, args.base_url):
                    if matches_callback(event, args.transaction_id, callback_action):
                        learn_identifiers(args, event)
                        return event
            except Exception as exc:
                print(f"  warn: observability poll failed: {exc}")
            time.sleep(args.poll_interval)
    return None


def run(args: argparse.Namespace) -> int:
    steps = flow_steps(args)
    print(f"flow={args.flow if not args.actions else 'custom'}")
    print(f"transaction_id={args.transaction_id}")
    print(f"workbench_base={args.workbench_base}")
    print(f"steps={', '.join(step.label for step in steps)}")

    for index, step in enumerate(steps, start=1):
        expected_callback = CALLBACK_FOR_ACTION[step.action]
        print(f"\n[{index}/{len(steps)}] sending {step.label}, expecting {expected_callback}")
        if args.dry_run:
            payload = workbench_trigger.build_payload(trigger_args(args, step))
            print(json.dumps(payload, indent=2))
            continue

        payload, response = send_signed_request(args, step)
        if workbench_412(response) and args.fallback_workbench_base:
            original_base = args.workbench_base
            original_version = args.version
            args.workbench_base = args.fallback_workbench_base
            args.version = args.fallback_version
            print(f"  no expectation at primary base; retrying {args.fallback_workbench_base}")
            payload, response = send_signed_request(args, step)
            if ack_status(response) != "ACK":
                args.workbench_base = original_base
                args.version = original_version
        status = ack_status(response)
        print(f"  request_message_id={payload['context']['message_id']}")
        print(f"  http_status={response.status_code} ack={status}")
        if status != "ACK":
            try:
                print(json.dumps(response.json(), indent=2))
            except Exception:
                print(response.text)
            return 1

        if args.no_wait:
            continue

        event = wait_for_callback(args, expected_callback)
        if not event:
            print(f"  timeout: did not observe {expected_callback} for {args.transaction_id}")
            return 2
        print(f"  observed {expected_callback}")
        if args.order_id:
            print(f"  order_id={args.order_id}")
        if args.provider_id or args.item_id:
            print(f"  provider_id={args.provider_id} item_id={args.item_id}")

    print("\nflow complete from Buyer-side automation")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Autopilot ONDC Workbench Buyer-side flow steps.")
    parser.add_argument("--list-flows", action="store_true")
    parser.add_argument("--flow", choices=sorted(FLOW_STEPS), default="rjt-wo-search-select")
    parser.add_argument("--actions", help="Comma-separated custom action list, e.g. search,init,confirm,status")
    parser.add_argument("--transaction-id", default=str(uuid.uuid4()))
    parser.add_argument("--base-url", default="https://ondc.metrosafar.in")
    parser.add_argument("--callback-timeout", type=float, default=45.0)
    parser.add_argument("--request-timeout", type=float, default=15.0)
    parser.add_argument("--poll-interval", type=float, default=2.0)
    parser.add_argument("--no-wait", action="store_true", help="Do not wait for MetroSafar to receive callbacks.")
    parser.add_argument("--dry-run", action="store_true")

    parser.add_argument("--workbench-base", default=workbench_trigger.DEFAULT_WORKBENCH_BASE)
    parser.add_argument("--fallback-workbench-base", default="https://workbench.ondc.tech/api-service/ONDC:TRV11/2.0.0/seller")
    parser.add_argument("--fallback-version", default="2.0.0")
    parser.add_argument("--bpp-id", default="workbench.ondc.tech")
    parser.add_argument("--omit-bpp-in-search", dest="include_bpp_in_search", action="store_false")
    parser.set_defaults(include_bpp_in_search=True)
    parser.add_argument("--subscriber-id", default="ondc.metrosafar.in")
    parser.add_argument("--subscriber-uri", default="https://ondc.metrosafar.in/ondc")
    parser.add_argument("--unique-key-id", default="d6acb12b-6334-4a01-8825-e5f1b60f01f5")
    parser.add_argument("--key-file", type=Path, default=workbench_trigger.DEFAULT_KEY_FILE)
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
    parser.add_argument("--reason-id", default="001")
    parser.add_argument("--cancel-code", default="SOFT_CANCEL")
    parser.add_argument("--cancel-name", default="Ride Cancellation")
    parser.add_argument("--update-target", default="order.fulfillments")
    parser.add_argument("--update-count", type=int, default=1)
    parser.add_argument("--fulfillment-id", default="F1")
    parser.add_argument("--fulfillment-state", default="CANCELLED")
    parser.add_argument("--static-terms-url", default="https://ondc.metrosafar.in/terms")
    parser.add_argument("--issue-id", default=None)
    parser.add_argument("--issue-status", default="OPEN")
    parser.add_argument("--issue-category", default="FULFILLMENT")
    parser.add_argument("--issue-short-desc", default="Ticket journey support")
    parser.add_argument("--issue-long-desc", default="Passenger needs assistance with the metro ticket journey.")
    parser.add_argument("--issue-resolution", default="Issue resolved by seller.")
    parser.add_argument("--issue-created-at", default=None)
    parser.add_argument("--rating", default="THUMBS-UP")

    args = parser.parse_args()
    if args.list_flows:
        for name, steps in sorted(FLOW_STEPS.items()):
            print(f"{name}: {', '.join(steps)}")
        raise SystemExit(0)
    if args.issue_id is None:
        args.issue_id = str(uuid.uuid4())
    return args


if __name__ == "__main__":
    sys.exit(run(parse_args()))
