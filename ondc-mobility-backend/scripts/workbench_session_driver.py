#!/usr/bin/env python3
"""
Drive the currently active ONDC Workbench flow from Workbench session state.

This complements workbench_autopilot.py. It does not create a Workbench flow;
start the flow in Workbench first, then run this script with the session id from
the URL. The script reads the active flow, transaction id, version, and next BAP
step from Workbench, then sends the corresponding signed Buyer request.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from copy import copy
from typing import Any

import httpx

import workbench_trigger


WORKBENCH_UI_BASE = "https://workbench.ondc.tech/backend-ui"
SUPPORTED_BAP_ACTIONS = {"search", "select", "init", "confirm", "status", "cancel", "update", "issue", "support"}
TICKET_CODE_FALLBACKS = {
    "SJT": {"item_id": "I1", "amount": "60"},
    "RJT": {"item_id": "I2", "amount": "110"},
}


def get_json(client: httpx.Client, url: str, *, params: dict[str, Any]) -> dict[str, Any]:
    response = client.get(url, params=params)
    response.raise_for_status()
    data = response.json()
    if not isinstance(data, dict):
        raise ValueError(f"Unexpected response from {url}: {type(data).__name__}")
    return data


def session_state(client: httpx.Client, session_id: str) -> dict[str, Any]:
    return get_json(client, f"{WORKBENCH_UI_BASE}/sessions", params={"session_id": session_id})


def current_flow_state(client: httpx.Client, session_id: str, transaction_id: str) -> dict[str, Any]:
    return get_json(
        client,
        f"{WORKBENCH_UI_BASE}/flow/current-state",
        params={"session_id": session_id, "transaction_id": transaction_id},
    )


def next_bap_step(flow_state: dict[str, Any]) -> dict[str, Any] | None:
    sequence = flow_state.get("sequence", [])
    pending_idx = None
    for idx, step in enumerate(sequence):
        if (
            step.get("owner") == "BAP"
            and step.get("actionType") in SUPPORTED_BAP_ACTIONS
            and step.get("status") in {"WAITING", "LISTENING"}
        ):
            pending_idx = idx
            break
    if pending_idx is None:
        return None
    for prior in sequence[:pending_idx]:
        if prior.get("status") not in {"COMPLETE", "SUCCESS"}:
            return None
    return sequence[pending_idx]


def summarize_steps(flow_state: dict[str, Any]) -> str:
    rows = []
    for step in flow_state.get("sequence", []):
        rows.append(
            f"{step.get('index')}: {step.get('actionId')} "
            f"({step.get('owner')}/{step.get('actionType')}) {step.get('status')}"
        )
    return "\n".join(rows)


def _iter_dicts(value: Any):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from _iter_dicts(item)
    elif isinstance(value, list):
        for item in value:
            yield from _iter_dicts(item)


def _ticket_code_for(flow_id: str, action_id: str) -> str | None:
    text = f"{flow_id} {action_id}".upper()
    if "RJT" in text or "RETURN" in text or "ROUND" in text:
        return "RJT"
    if "SJT" in text or "SINGLE" in text:
        return "SJT"
    return None


def _item_ticket_code(item: dict[str, Any]) -> str | None:
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


def _catalog_ticket_selection(flow_state: dict[str, Any] | None, ticket_code: str) -> dict[str, str] | None:
    if not flow_state:
        return None
    for candidate in _iter_dicts(flow_state):
        items = candidate.get("items")
        if not isinstance(items, list):
            continue
        provider_id = candidate.get("id") if isinstance(candidate.get("id"), str) else None
        for item in items:
            if not isinstance(item, dict) or _item_ticket_code(item) != ticket_code:
                continue
            item_id = item.get("id")
            if not item_id:
                continue
            price = item.get("price") if isinstance(item.get("price"), dict) else {}
            selection = {"item_id": str(item_id)}
            if provider_id:
                selection["provider_id"] = provider_id
            if price.get("value") is not None:
                selection["amount"] = str(price["value"])
            return selection
    return None


def _apply_ticket_selection(args: argparse.Namespace, action: str, flow_state: dict[str, Any] | None) -> None:
    if action not in {"select", "init", "confirm", "update"}:
        return
    ticket_code = _ticket_code_for(getattr(args, "flow_id", ""), getattr(args, "action_id", ""))
    if not ticket_code:
        return
    selection = _catalog_ticket_selection(flow_state, ticket_code) or TICKET_CODE_FALLBACKS[ticket_code]
    args.item_id = selection["item_id"]
    if selection.get("provider_id"):
        args.provider_id = selection["provider_id"]
    if selection.get("amount"):
        args.amount = selection["amount"]


def configure_step_args(base_args: argparse.Namespace, session: dict[str, Any], step: dict[str, Any], flow_state: dict[str, Any] | None = None) -> argparse.Namespace:
    args = copy(base_args)
    action = step["actionType"]
    action_id = step.get("actionId", "")
    args.action_id = action_id
    args.action = action

    args.flow_id = str(base_args.flow_id or session.get("activeFlow") or "")
    args.domain = str(session.get("domain") or getattr(args, "domain", "ONDC:TRV11")).strip("/")
    args.version = str(session.get("version") or getattr(args, "version", "2.0.0")).strip("/")

    args.subscriber_uri = str(session.get("subscriberUrl") or args.subscriber_uri)
    args.workbench_base = (
        f"https://workbench.ondc.tech/api-service/"
        f"{args.domain}/{args.version}/seller"
    )
    args.catalog = action == "search" and "search1" in action_id
    if action == "search" and "search1" in action_id.lower():
        args.include_bpp_in_search = False
    elif action == "search":
        args.include_bpp_in_search = True

    if action == "issue":
        action_id_lower = action_id.lower()
        args.issue_status = "CLOSED" if "close" in action_id_lower else "OPEN"
        if "info" in action_id_lower:
            args.issue_action = "INFO_PROVIDED"
            args.issue_short_desc = "Additional ticket details provided"
            args.issue_long_desc = "Passenger provided additional details requested for the metro ticket issue."
        elif "accept" in action_id_lower:
            args.issue_action = "RESOLUTION_ACCEPTED"
            args.issue_short_desc = "Resolution accepted"
            args.issue_long_desc = "Passenger accepted the proposed issue resolution."
        elif "reject" in action_id_lower:
            args.issue_action = "RESOLUTION_REJECTED"
            args.issue_short_desc = "Resolution rejected"
            args.issue_long_desc = "Passenger rejected the proposed issue resolution."
        elif "escalate" in action_id_lower:
            args.issue_action = "ESCALATE"
            args.issue_short_desc = "Issue escalated"
            args.issue_long_desc = "Passenger escalated the issue."
        elif "close" in action_id_lower:
            args.issue_action = "CLOSE"
            args.issue_short_desc = "Issue closed"
            args.issue_long_desc = "Passenger closed the metro ticket issue."
        else:
            args.issue_action = "OPEN"

        comp_actions = []
        resp_actions = []
        if flow_state:
            for s in flow_state.get("sequence", []):
                p_obj = s.get("payloads") or {}
                p_list = p_obj.get("payloads") or []
                for item in p_list:
                    req = item.get("request") or item.get("payload") or {}
                    msg_issue = req.get("message", {}).get("issue", {})
                    if msg_issue:
                        act_obj = msg_issue.get("issue_actions", {})
                        for ca in act_obj.get("complainant_actions") or []:
                            if ca not in comp_actions:
                                comp_actions.append(ca)
                        for ra in act_obj.get("respondent_actions") or []:
                            if ra not in resp_actions:
                                resp_actions.append(ra)

        args.past_complainant_actions = comp_actions
        args.past_respondent_actions = resp_actions

    if flow_state:
        msg_ids = {}
        for s in flow_state.get("sequence", []):
            p_obj = s.get("payloads") or {}
            p_list = p_obj.get("payloads") or []
            for item in p_list:
                req = item.get("request") or item.get("payload") or {}
                ctx = req.get("context") or {}
                if ctx.get("action") and ctx.get("message_id"):
                    msg_ids[ctx["action"]] = ctx["message_id"]

        if args.version.startswith("2.0.0"):
            if action == "init" and "search" in msg_ids:
                args.message_id = msg_ids["search"]
            elif action == "confirm" and "init" in msg_ids:
                args.message_id = msg_ids["init"]
            elif action == "status" and "confirm" in msg_ids:
                args.message_id = msg_ids["confirm"]

    if action == "cancel":
        if "tech" in action_id.lower() or "hard" in action_id.lower():
            args.cancel_code = "CONFIRM_CANCEL"
            args.cancel_name = "Confirm Cancellation"
        else:
            args.cancel_code = "SOFT_CANCEL"
            args.cancel_name = "Ride Cancellation"
    if action == "update" and "partial_cancellation" in action_id.lower():
        args.fulfillment_id = "F2"
        args.reason_id = "001"
    _apply_ticket_selection(args, action, flow_state)
    return args


def send_signed(args: argparse.Namespace) -> tuple[dict[str, Any], httpx.Response]:
    payload = workbench_trigger.build_payload(args)
    body = json.dumps(payload, separators=(",", ":")).encode()
    private_key = workbench_trigger.load_private_key(args.key_file)
    headers = workbench_trigger.auth_headers(body, args.subscriber_id, args.unique_key_id, private_key)
    url = f"{args.workbench_base.rstrip('/')}/{args.action}"
    with httpx.Client(timeout=args.request_timeout) as client:
        response = client.post(url, content=body, headers=headers)
    return payload, response


def run_once(args: argparse.Namespace, client: httpx.Client) -> bool:
    session = session_state(client, args.session_id)
    flow_id = args.flow_id or session.get("activeFlow")
    if not flow_id or flow_id == "NONE":
        raise RuntimeError("No active Workbench flow. Start a flow in the Workbench UI first.")

    flow_map = session.get("flowMap") or {}
    transaction_id = args.transaction_id or flow_map.get(flow_id)
    if not transaction_id:
        raise RuntimeError(f"No transaction id found for active flow {flow_id!r}. Press the play/start button in Workbench first.")

    args.transaction_id = transaction_id
    flow_state = current_flow_state(client, args.session_id, transaction_id)
    step = next_bap_step(flow_state)

    print(f"session_id={args.session_id}")
    print(f"flow_id={flow_id}")
    print(f"transaction_id={transaction_id}")
    print(f"session_version={session.get('version')}")
    if not step:
        print("No waiting BAP step found.")
        print(summarize_steps(flow_state))
        return False

    step_args = configure_step_args(args, session, step, flow_state=flow_state)
    print(f"next_step={step.get('actionId')} action={step_args.action} version={step_args.version}")
    if args.dry_run:
        print(json.dumps(workbench_trigger.build_payload(step_args), indent=2))
        return True

    payload, response = send_signed(step_args)
    print(f"request_message_id={payload['context']['message_id']}")
    print(f"http_status={response.status_code}")
    try:
        print(json.dumps(response.json(), indent=2))
    except Exception:
        print(response.text)

    return response.status_code < 400 and response.json().get("message", {}).get("ack", {}).get("status") == "ACK"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send the next BAP request for an active Workbench session.")
    parser.add_argument("--session-id", required=True, help="Workbench sessionId from the flow-testing URL.")
    parser.add_argument("--flow-id", help="Workbench flow id. Defaults to session activeFlow.")
    parser.add_argument("--transaction-id", help="Override transaction id; defaults to session flowMap[activeFlow].")
    parser.add_argument("--until-done", action="store_true", help="Keep sending the next BAP step until none remains or an error occurs.")
    parser.add_argument("--delay", type=float, default=4.0, help="Delay between steps in --until-done mode.")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--request-timeout", type=float, default=20.0)

    parser.add_argument("--subscriber-id", default="ondc.metrosafar.in")
    parser.add_argument("--subscriber-uri", default="https://ondc.metrosafar.in/ondc")
    parser.add_argument("--unique-key-id", default="d6acb12b-6334-4a01-8825-e5f1b60f01f5")
    parser.add_argument("--key-file", type=workbench_trigger.Path, default=workbench_trigger.DEFAULT_KEY_FILE)
    parser.add_argument("--bpp-id", default="workbench.ondc.tech")
    parser.add_argument("--domain", default="ONDC:TRV11")
    parser.add_argument("--version", default="2.0.0")
    parser.add_argument("--country-code", default="IND")
    parser.add_argument("--city-code", default="std:040")
    parser.add_argument("--origin", default="MOCK_STATION_1")
    parser.add_argument("--destination", default="MOCK_STATION_2")
    parser.add_argument("--provider-id", default="P1")
    parser.add_argument("--item-id", default="I1")
    parser.add_argument("--fulfillment-id", default="F1")
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
    parser.set_defaults(include_bpp_in_search=True)

    args = parser.parse_args()
    if args.issue_id is None:
        args.issue_id = workbench_trigger.uuid.uuid4().hex
    return args


def main() -> int:
    args = parse_args()
    with httpx.Client(timeout=args.request_timeout) as client:
        while True:
            ok = run_once(args, client)
            if not args.until_done or not ok:
                return 0 if ok else 1
            time.sleep(args.delay)


if __name__ == "__main__":
    sys.exit(main())
