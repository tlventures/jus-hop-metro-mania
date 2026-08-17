#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import httpx

import workbench_session_driver as driver
import workbench_trigger


WORKBENCH_UI_BASE = "https://workbench.ondc.tech/backend-ui"


def get_with_retry(client: httpx.Client, url: str, *, params: dict[str, Any], attempts: int = 5) -> httpx.Response:
    last_exc: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            response = client.get(url, params=params)
            if response.status_code < 500:
                response.raise_for_status()
                return response
            last_exc = httpx.HTTPStatusError(
                f"Server error '{response.status_code}' for url '{response.url}'",
                request=response.request,
                response=response,
            )
        except (httpx.HTTPError, httpx.TimeoutException) as exc:
            last_exc = exc
        if attempt < attempts:
            time.sleep(min(2 * attempt, 8))
    if last_exc:
        raise last_exc
    raise RuntimeError(f"Unable to fetch {url}")


def base_args(args: argparse.Namespace) -> SimpleNamespace:
    return SimpleNamespace(
        session_id=args.session_id,
        flow_id=None,
        transaction_id=None,
        dry_run=False,
        request_timeout=args.request_timeout,
        subscriber_id=args.subscriber_id,
        subscriber_uri=args.subscriber_uri,
        unique_key_id=args.unique_key_id,
        key_file=args.key_file,
        bpp_id="workbench.ondc.tech",
        domain="ONDC:TRV11",
        version=args.version,
        country_code=args.country_code,
        city_code=args.city_code,
        origin=args.origin,
        destination=args.destination,
        provider_id=args.provider_id,
        item_id=args.item_id,
        fulfillment_id=args.fulfillment_id,
        passenger_count=args.passenger_count,
        passenger_name=args.passenger_name,
        passenger_phone=args.passenger_phone,
        passenger_email=args.passenger_email,
        amount=args.amount,
        payment_id=None,
        payment_txn_id=None,
        order_id=args.order_id,
        reason_id=args.reason_id,
        cancel_code="SOFT_CANCEL",
        cancel_name="Ride Cancellation",
        update_target="order.fulfillments",
        update_count=args.update_count,
        update_end_code=args.update_end_code,
        fulfillment_state="CANCELLED",
        static_terms_url=args.static_terms_url,
        issue_id=None,
        issue_status="OPEN",
        issue_category="FULFILLMENT",
        issue_sub_category="FLM101",
        issue_type="ISSUE",
        issue_action=None,
        issue_short_desc="Ticket journey support",
        issue_long_desc="Passenger needs assistance with the metro ticket journey.",
        issue_resolution="Issue resolved by seller.",
        issue_expected_response_time="PT2H",
        issue_expected_resolution_time="P1D",
        issue_created_at=None,
        issue_fulfillment_state="UNCLAIMED",
        rating="THUMBS-UP",
        include_bpp_in_search=True,
    )


def session_state(client: httpx.Client, session_id: str) -> dict[str, Any]:
    response = get_with_retry(client, f"{WORKBENCH_UI_BASE}/sessions", params={"session_id": session_id})
    return response.json()


def current_state(client: httpx.Client, session_id: str, transaction_id: str) -> dict[str, Any]:
    response = get_with_retry(
        client,
        f"{WORKBENCH_UI_BASE}/flow/current-state",
        params={"session_id": session_id, "transaction_id": transaction_id},
    )
    return response.json()


def start_flow(client: httpx.Client, session_id: str, flow_id: str, subscriber_url: str) -> str:
    transaction_id = str(uuid.uuid4())
    cleanup = [
        ("DELETE", f"{WORKBENCH_UI_BASE}/sessions/expectation", {"params": {"session_id": session_id, "subscriber_url": subscriber_url}}),
        ("PUT", f"{WORKBENCH_UI_BASE}/sessions", {"params": {"session_id": session_id}, "json": {"activeFlow": "NONE"}}),
        ("DELETE", f"{WORKBENCH_UI_BASE}/sessions/clearFlow", {"params": {"session_id": session_id, "flow_id": flow_id}}),
    ]
    for method, url, kwargs in cleanup:
        client.request(method, url, **kwargs)
    response = client.post(
        f"{WORKBENCH_UI_BASE}/flow/new",
        json={"session_id": session_id, "flow_id": flow_id, "transaction_id": transaction_id},
    )
    response.raise_for_status()
    client.put(f"{WORKBENCH_UI_BASE}/sessions", params={"session_id": session_id}, json={"activeFlow": flow_id}).raise_for_status()
    return transaction_id


def flow_names(session: dict[str, Any], requested: list[str]) -> list[str]:
    configs = session.get("flowConfigs") or {}
    if requested:
        wanted = set(requested)
        names = [name for name in configs.keys() if name in wanted]
    else:
        names = [
            name
            for name, cfg in configs.items()
            if "WORKBENCH" in (cfg.get("tags") or [])
        ]
    return sorted(names)


def expected_error_action_ids(flow_id: str) -> set[str]:
    if "TECHNICAL_CANCELLATION_FLOW" in flow_id:
        return {"on_confirm_delayed_METRO_200"}
    return set()


def complete(flow_state: dict[str, Any], flow_id: str) -> bool:
    sequence = flow_state.get("sequence") or []
    if not sequence:
        return False

    bap_steps = [s for s in sequence if s.get("owner") == "BAP"]
    if not bap_steps or not all(s.get("status") == "COMPLETE" for s in bap_steps):
        return False

    expected_errors = expected_error_action_ids(flow_id)
    if any(
        (s.get("payloads") or {}).get("subStatus") == "ERROR"
        and s.get("actionId") not in expected_errors
        for s in sequence
    ):
        return False

    if flow_state.get("extraSteps"):
        return False

    non_bap_steps = [s for s in sequence if s.get("owner") != "BAP"]
    return all(
        s.get("status") in {"COMPLETE", "SUCCESS"}
        for s in non_bap_steps
        if s.get("actionId") not in expected_errors
    )


def unexpected_error_steps(flow_state: dict[str, Any], flow_id: str) -> list[dict[str, Any]]:
    expected_errors = expected_error_action_ids(flow_id)
    return [
        s
        for s in flow_state.get("sequence") or []
        if (s.get("payloads") or {}).get("subStatus") == "ERROR"
        and s.get("actionId") not in expected_errors
    ]


def input_required_bpp_step(flow_state: dict[str, Any]) -> dict[str, Any] | None:
    for step in flow_state.get("sequence") or []:
        if step.get("owner") != "BAP" and step.get("status") in {"INPUT-REQUIRED", "INACTIVE"}:
            return step
    return None


def proceed_flow(client: httpx.Client, args: argparse.Namespace, transaction_id: str) -> dict[str, Any]:
    response = client.post(
        f"{WORKBENCH_UI_BASE}/flow/proceed",
        json={
            "session_id": args.session_id,
            "transaction_id": transaction_id,
            "json_path_changes": {},
            "inputs": {},
        },
    )
    response.raise_for_status()
    data = response.json()
    return data if isinstance(data, dict) else {}


def summarize(flow_state: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for step in flow_state.get("sequence") or []:
        payloads = step.get("payloads") or {}
        rows.append(
            {
                "index": step.get("index"),
                "actionId": step.get("actionId"),
                "owner": step.get("owner"),
                "actionType": step.get("actionType"),
                "status": step.get("status"),
                "subStatus": payloads.get("subStatus"),
            }
        )
    return rows


def run_flow(client: httpx.Client, args: argparse.Namespace, flow_id: str) -> dict[str, Any]:
    session = session_state(client, args.session_id)
    first_step = next(
        (
            {
                "actionId": step.get("key"),
                "owner": step.get("owner"),
                "actionType": step.get("type"),
                "status": "WAITING",
            }
            for step in (session.get("flowConfigs", {}).get(flow_id, {}).get("sequence") or [])
            if step.get("owner") == "BAP"
        ),
        None,
    )
    if not first_step:
        return {"flow": flow_id, "ok": False, "error": "No BAP step found in flow config"}

    transaction_id = start_flow(client, args.session_id, flow_id, args.subscriber_uri)
    result: dict[str, Any] = {"flow": flow_id, "transaction_id": transaction_id, "steps_sent": [], "ok": False}
    base = base_args(args)
    base.flow_id = flow_id
    base.transaction_id = transaction_id
    if "IGM" in flow_id:
        base.issue_id = str(uuid.uuid4())
        base.issue_created_at = workbench_trigger.now_iso()

    last_state: dict[str, Any] = {}
    step_args = driver.configure_step_args(base, session, first_step)
    payload, response = driver.send_signed(step_args)
    try:
        response_json = response.json()
    except Exception:
        response_json = {"raw": response.text}
    ack = response_json.get("message", {}).get("ack", {}).get("status")
    result["steps_sent"].append(
        {
            "actionId": first_step.get("actionId"),
            "action": step_args.action,
            "message_id": payload["context"]["message_id"],
            "http_status": response.status_code,
            "ack": ack,
            "response": response_json,
        }
    )
    print(f"  {first_step.get('actionId')} {step_args.action}: HTTP {response.status_code} {ack}", flush=True)
    if response.status_code >= 400 or ack != "ACK":
        result["error"] = "Initial BAP request was not ACKed"
        return result
    sent_action_ids = {first_step.get("actionId")}
    proceeded_action_ids: set[str] = set()
    start_time = time.time()
    max_flow_seconds = args.max_flow_seconds

    while time.time() - start_time < max_flow_seconds:
        flow_state = current_state(client, args.session_id, transaction_id)
        last_state = flow_state
        driver.learn_identifiers_from_flow_state(base, client, flow_state)

        errors = unexpected_error_steps(flow_state, flow_id)
        if errors:
            result["error"] = "Flow reported ERROR subStatus"
            result["summary"] = summarize(flow_state)
            result["errorSteps"] = [step.get("actionId") for step in errors]
            return result

        proceed_step = input_required_bpp_step(flow_state)
        proceed_action_id = proceed_step.get("actionId") if proceed_step else None
        if proceed_action_id and proceed_action_id not in proceeded_action_ids:
            proceeded_action_ids.add(proceed_action_id)
            proceed_response = proceed_flow(client, args, transaction_id)
            result.setdefault("proceeded_steps", []).append(
                {
                    "actionId": proceed_action_id,
                    "response": proceed_response,
                }
            )
            print(f"  {proceed_action_id} proceed: {proceed_response.get('success')}", flush=True)
            time.sleep(args.poll_delay)
            continue

        if complete(flow_state, flow_id):
            result["ok"] = True
            result["summary"] = summarize(flow_state)
            return result

        step = driver.next_bap_step(flow_state)
        if step and step.get("actionId") not in sent_action_ids:
            sent_action_ids.add(step.get("actionId"))
            step_args = driver.configure_step_args(base, session_state(client, args.session_id), step, flow_state=flow_state)
            payload, response = driver.send_signed(step_args)
            try:
                response_json = response.json()
            except Exception:
                response_json = {"raw": response.text}
            ack = response_json.get("message", {}).get("ack", {}).get("status")
            result["steps_sent"].append(
                {
                    "actionId": step.get("actionId"),
                    "action": step_args.action,
                    "message_id": payload["context"]["message_id"],
                    "http_status": response.status_code,
                    "ack": ack,
                    "response": response_json,
                }
            )
            print(f"  {step.get('actionId')} {step_args.action}: HTTP {response.status_code} {ack}", flush=True)
            if response.status_code >= 400 or ack != "ACK":
                result["error"] = "BAP request was not ACKed"
                result["summary"] = summarize(current_state(client, args.session_id, transaction_id))
                return result

        time.sleep(args.poll_delay)

    result["error"] = f"Flow timed out after {max_flow_seconds}s"
    result["summary"] = summarize(last_state)
    result["missedSteps"] = last_state.get("missedSteps")
    result["extraSteps"] = last_state.get("extraSteps")
    return result
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run all reportable ONDC Workbench Metro flows.")
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--flow", action="append", default=[])
    parser.add_argument("--subscriber-id", default="ondc.metrosafar.in")
    parser.add_argument("--subscriber-uri", default="https://ondc.metrosafar.in/ondc")
    parser.add_argument("--unique-key-id", default="d6acb12b-6334-4a01-8825-e5f1b60f01f5")
    parser.add_argument("--key-file", type=Path, default=workbench_trigger.DEFAULT_KEY_FILE)
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
    parser.add_argument("--order-id", default="077b248f")
    parser.add_argument("--reason-id", default="001")
    parser.add_argument("--update-count", type=int, default=1)
    parser.add_argument("--update-end-code", default="MOCK_STATION_5")
    parser.add_argument("--static-terms-url", default="https://ondc.metrosafar.in/terms")
    parser.add_argument("--poll-delay", type=float, default=2.0)
    parser.add_argument("--final-wait-polls", type=int, default=35)
    parser.add_argument("--max-flow-seconds", type=float, default=240.0)
    parser.add_argument("--max-steps", type=int, default=40)
    parser.add_argument("--request-timeout", type=float, default=20.0)
    parser.add_argument("--output", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output or Path(f"workbench-flow-results-{int(time.time())}.json")
    results = []
    with httpx.Client(timeout=args.request_timeout, headers={"user-agent": "Mozilla/5.0"}) as client:
        session = session_state(client, args.session_id)
        names = flow_names(session, args.flow)
        print(f"Running {len(names)} flow(s)")
        for index, flow_id in enumerate(names, 1):
            print(f"[{index}/{len(names)}] {flow_id}", flush=True)
            try:
                result = run_flow(client, args, flow_id)
            except Exception as exc:
                result = {"flow": flow_id, "ok": False, "error": f"{type(exc).__name__}: {exc}"}
            print(f"  result: {'PASS' if result.get('ok') else 'FAIL'}", flush=True)
            results.append(result)
            output.write_text(json.dumps(results, indent=2))
    failed = [result for result in results if not result.get("ok")]
    print(f"wrote {output}")
    print(f"passed={len(results) - len(failed)} failed={len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
