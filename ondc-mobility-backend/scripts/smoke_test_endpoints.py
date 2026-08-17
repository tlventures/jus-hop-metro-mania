#!/usr/bin/env python3
"""
Smoke-test MetroSafar ONDC BAP endpoints before ONDC portal / Pramaan testing.

Default target:
    https://ondc.metrosafar.in

This script intentionally separates:
1. Safe public checks that do not require a real ONDC seller.
2. Optional outbound transaction checks that require Pramaan or a mock BPP.

Usage:
    python scripts/smoke_test_endpoints.py
    python scripts/smoke_test_endpoints.py --base-url https://ondc.metrosafar.in
    python scripts/smoke_test_endpoints.py --subscribe-challenge '<encrypted_challenge>'
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from dataclasses import dataclass
from typing import Any, Callable

import httpx


DEFAULT_BASE_URL = "https://ondc.metrosafar.in"
USER_HEADER = {"x-user-phone-hash": "metrosafar_smoke_user"}


@dataclass
class CheckResult:
    name: str
    ok: bool
    status_code: int | None = None
    detail: str = ""


class SmokeTester:
    def __init__(self, base_url: str, timeout: float, subscribe_challenge: str | None):
        self.base_url = base_url.rstrip("/")
        self.subscribe_challenge = subscribe_challenge
        self.strict_verification_file = False
        self.results: list[CheckResult] = []
        self.client = httpx.Client(timeout=timeout, follow_redirects=False)
        self.transaction_id = str(uuid.uuid4())

    def close(self) -> None:
        self.client.close()

    def _record(self, name: str, ok: bool, response: httpx.Response | None = None, detail: str = "") -> None:
        self.results.append(CheckResult(
            name=name,
            ok=ok,
            status_code=response.status_code if response else None,
            detail=detail,
        ))
        prefix = "PASS" if ok else "FAIL"
        status = f" HTTP {response.status_code}" if response else ""
        extra = f" - {detail}" if detail else ""
        print(f"[{prefix}] {name}{status}{extra}")

    def _expect_json(
        self,
        name: str,
        method: str,
        path: str,
        *,
        expected_status: set[int],
        json_body: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
        validator: Callable[[Any], tuple[bool, str]] | None = None,
    ) -> Any:
        url = f"{self.base_url}{path}"
        try:
            response = self.client.request(method, url, json=json_body, headers=headers)
        except Exception as exc:
            self._record(name, False, detail=str(exc))
            return None

        try:
            data = response.json()
        except Exception:
            data = response.text

        ok = response.status_code in expected_status
        detail = ""
        if ok and validator:
            ok, detail = validator(data)
        elif not ok:
            detail = f"expected {sorted(expected_status)}, got body={data!r}"

        self._record(name, ok, response, detail)
        return data

    @staticmethod
    def _ack_validator(data: Any) -> tuple[bool, str]:
        status = data.get("message", {}).get("ack", {}).get("status") if isinstance(data, dict) else None
        if status == "ACK":
            return True, ""
        return False, f"expected ACK body, got {data!r}"

    @staticmethod
    def _health_validator(data: Any) -> tuple[bool, str]:
        if isinstance(data, dict) and data.get("status") == "HEALTHY" and data.get("domain") == "ONDC:TRV11":
            return True, ""
        return False, f"unexpected health payload {data!r}"

    def context(self, action: str) -> dict[str, Any]:
        return {
            "domain": "ONDC:TRV11",
            "location": {
                "country": {"code": "IND"},
                "city": {"code": "std:040"},
            },
            "action": action,
            "version": "2.0.0",
            "bap_id": "ondc.metrosafar.in",
            "bap_uri": "https://ondc.metrosafar.in/ondc",
            "bpp_id": "smoke-bpp",
            "bpp_uri": "https://seller.example/ondc",
            "transaction_id": self.transaction_id,
            "message_id": f"smoke-{action}-{uuid.uuid4()}",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "ttl": "PT30S",
        }

    def run_foundation_checks(self) -> None:
        self._expect_json(
            "GET /health",
            "GET",
            "/health",
            expected_status={200},
            validator=self._health_validator,
        )
        self._expect_json("GET /ready", "GET", "/ready", expected_status={200})

        try:
            response = self.client.get(f"{self.base_url}/ondc-site-verification.html")
            has_placeholder = "placeholder" in response.text.lower()
            ok = response.status_code == 200 and (not has_placeholder or not self.strict_verification_file)
            detail = "WARN: reachable, but still appears to contain placeholder verification content" if has_placeholder else ""
            self._record("GET /ondc-site-verification.html", ok, response, detail)
        except Exception as exc:
            self._record("GET /ondc-site-verification.html", False, detail=str(exc))

        if self.subscribe_challenge:
            self._expect_json(
                "POST /ondc/on_subscribe with supplied challenge",
                "POST",
                "/ondc/on_subscribe",
                expected_status={200},
                json_body={"challenge": self.subscribe_challenge},
                validator=lambda data: (isinstance(data, dict) and bool(data.get("answer")), f"body={data!r}"),
            )
        else:
            self._expect_json(
                "POST /ondc/on_subscribe validation",
                "POST",
                "/ondc/on_subscribe",
                expected_status={400},
                json_body={},
            )

    def run_callback_checks(self) -> None:
        payloads: dict[str, dict[str, Any]] = {
            "on_search": {
                "message": {
                    "catalog": {
                        "bpp_providers": [{
                            "id": "HYD_METRO_OPERATOR",
                            "descriptor": {"name": "Hyderabad Metro"},
                            "items": [{"id": "SJT_01", "descriptor": {"name": "Single Journey"}, "price": {"currency": "INR", "value": "50.00"}}],
                        }]
                    }
                }
            },
            "on_select": {"message": {"order": {"quote": {"price": {"currency": "INR", "value": "50.00"}, "breakup": []}}}},
            "on_init": {"message": {"order": {"id": "ORDER-SMOKE", "state": "INITIATED"}}},
            "on_confirm": {
                "message": {
                    "order": {
                        "id": "ORDER-SMOKE",
                        "state": "ACCEPTED",
                        "fulfillments": [{
                            "id": "F1",
                            "type": "RIDE",
                            "stops": [{"location": {"id": "START"}}, {"location": {"id": "END"}}],
                            "tokens": [{"token": "SMOKE_QR_TOKEN"}],
                        }],
                    }
                }
            },
            "on_status": {"message": {"order": {"id": "ORDER-SMOKE", "state": "ACTIVE"}}},
            "on_cancel": {"message": {"order": {"id": "ORDER-SMOKE", "state": "CANCELLED"}}},
            "on_update": {"message": {"order": {"id": "ORDER-SMOKE", "state": "UPDATED"}}},
            "on_track": {"message": {"tracking": {"id": "TRACK-SMOKE", "status": "active"}}},
            "on_support": {"message": {"support": {"type": "order", "ref_id": "ORDER-SMOKE"}}},
            "on_rating": {"message": {"ratings": [{"id": "ORDER-SMOKE", "value": "5"}]}},
            "on_issue": {"message": {"issue": {"id": str(uuid.uuid4()), "status": "ACKNOWLEDGED"}}},
            "on_issue_status": {"message": {"issue": {"id": str(uuid.uuid4()), "status": "PROCESSING"}}},
            "on_receiver_recon": {
                "message": {
                    "orderbook": {
                        "orders": [{
                            "id": "ORDER-SMOKE",
                            "transaction_id": self.transaction_id,
                            "payment_id": "PAY-SMOKE",
                            "receiver": "seller-app",
                            "withholding_amount": {"currency": "INR", "value": "1.00"},
                            "settlement_amount": {"currency": "INR", "value": "49.00"},
                            "refund_amount": {"currency": "INR", "value": "0.00"},
                        }]
                    }
                }
            },
            "on_settle": {
                "message": {
                    "settlement": {
                        "orders": [{
                            "id": "ORDER-SMOKE",
                            "transaction_id": self.transaction_id,
                            "amount": {"currency": "INR", "value": "49.00"},
                            "settlement_party": "seller-app",
                            "settlement_reference": f"SETTLE-{uuid.uuid4()}",
                            "status": "PAID",
                        }]
                    }
                }
            },
        }

        for action, body in payloads.items():
            payload = {"context": self.context(action), **body}
            self._expect_json(
                f"POST /ondc/{action}",
                "POST",
                f"/ondc/{action}",
                expected_status={200},
                json_body=payload,
                validator=self._ack_validator,
            )

    def run_mobile_and_admin_checks(self) -> None:
        search = self._expect_json(
            "POST /api/v1/search",
            "POST",
            "/api/v1/search",
            expected_status={200},
            headers=USER_HEADER,
            json_body={
                "origin_station_id": "STATION_CODE_FLOW",
                "destination_station_id": "CATALOG",
                "city_code": "std:040",
            },
            validator=lambda data: (isinstance(data, dict) and data.get("status") == "SEARCH_INITIATED", f"body={data!r}"),
        )
        if isinstance(search, dict) and search.get("transaction_id"):
            self.transaction_id = search["transaction_id"]

        issue = self._expect_json(
            "POST /api/v1/issues",
            "POST",
            "/api/v1/issues",
            expected_status={201},
            headers=USER_HEADER,
            json_body={
                "transaction_id": self.transaction_id,
                "order_id": "ORDER-SMOKE",
                "category": "QR_NOT_ACCEPTED",
                "description": "Smoke test issue",
                "send_to_network": False,
            },
            validator=lambda data: (isinstance(data, dict) and bool(data.get("issue_id")), f"body={data!r}"),
        )
        issue_id = issue.get("issue_id") if isinstance(issue, dict) else None

        self._expect_json("GET /api/v1/issues", "GET", "/api/v1/issues", expected_status={200})
        if issue_id:
            self._expect_json(
                "PATCH /api/v1/issues/{issue_id}",
                "PATCH",
                f"/api/v1/issues/{issue_id}",
                expected_status={200},
                json_body={"status": "PROCESSING", "note": "Smoke test update"},
            )

        recon = self._expect_json(
            "POST /api/v1/recon",
            "POST",
            "/api/v1/recon",
            expected_status={201},
            json_body={
                "transaction_id": self.transaction_id,
                "order_id": "ORDER-SMOKE",
                "payment_txn_id": "PAY-SMOKE",
                "buyer_finder_fee": "1.00",
                "settlement_party": "seller-app",
                "settlement_amount": "49.00",
                "refund_adjustment": "0.00",
                "status": "PENDING",
            },
            validator=lambda data: (isinstance(data, dict) and bool(data.get("recon_id")), f"body={data!r}"),
        )
        recon_id = recon.get("recon_id") if isinstance(recon, dict) else None
        self._expect_json("GET /api/v1/recon", "GET", "/api/v1/recon", expected_status={200})
        if recon_id:
            self._expect_json(
                "PATCH /api/v1/recon/{recon_id}",
                "PATCH",
                f"/api/v1/recon/{recon_id}",
                expected_status={200},
                json_body={
                    "transaction_id": self.transaction_id,
                    "order_id": "ORDER-SMOKE",
                    "payment_txn_id": "PAY-SMOKE",
                    "buyer_finder_fee": "1.00",
                    "settlement_party": "seller-app",
                    "settlement_amount": "49.00",
                    "refund_adjustment": "0.00",
                    "status": "RECONCILED",
                    "details": {"smoke": True},
                },
            )

        payout = self._expect_json(
            "POST /api/v1/payouts",
            "POST",
            "/api/v1/payouts",
            expected_status={201},
            json_body={
                "recon_id": recon_id,
                "transaction_id": self.transaction_id,
                "order_id": "ORDER-SMOKE",
                "settlement_party": "seller-app",
                "amount": "49.00",
                "currency": "INR",
                "payout_reference": f"PAYOUT-{uuid.uuid4()}",
                "status": "PENDING",
                "send_to_network": False,
            },
            validator=lambda data: (isinstance(data, dict) and bool(data.get("payout_id")), f"body={data!r}"),
        )
        payout_id = payout.get("payout_id") if isinstance(payout, dict) else None
        self._expect_json("GET /api/v1/payouts", "GET", "/api/v1/payouts", expected_status={200})
        if payout_id:
            self._expect_json(
                "PATCH /api/v1/payouts/{payout_id}",
                "PATCH",
                f"/api/v1/payouts/{payout_id}",
                expected_status={200},
                json_body={
                    "recon_id": recon_id,
                    "transaction_id": self.transaction_id,
                    "order_id": "ORDER-SMOKE",
                    "settlement_party": "seller-app",
                    "amount": "49.00",
                    "currency": "INR",
                    "payout_reference": f"PAYOUT-{uuid.uuid4()}",
                    "status": "INITIATED",
                    "send_to_network": False,
                },
            )

        self._expect_json("GET /api/v1/tickets", "GET", "/api/v1/tickets", expected_status={200}, headers=USER_HEADER)
        self._expect_json("GET /api/v1/observability", "GET", "/api/v1/observability", expected_status={200})
        self._expect_json("POST /api/v1/observability/submit", "POST", "/api/v1/observability/submit", expected_status={200})
        self._expect_json(
            "GET /api/v1/compliance/readiness",
            "GET",
            "/api/v1/compliance/readiness",
            expected_status={200},
            validator=lambda data: (
                isinstance(data, dict)
                and all(component.get("built") for component in data.get("components", {}).values()),
                f"body={json.dumps(data)[:500]}",
            ),
        )

    def print_summary(self) -> int:
        failed = [result for result in self.results if not result.ok]
        print("")
        print("=" * 72)
        print(f"Smoke test complete: {len(self.results) - len(failed)}/{len(self.results)} passed")
        if failed:
            print("Failures:")
            for result in failed:
                status = f"HTTP {result.status_code}" if result.status_code else "no response"
                print(f"  - {result.name}: {status} {result.detail}")
            print("=" * 72)
            return 1
        print("All checks passed.")
        print("=" * 72)
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test MetroSafar ONDC public endpoints.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Base URL to test. Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout in seconds.")
    parser.add_argument(
        "--subscribe-challenge",
        default=None,
        help="Optional encrypted ONDC on_subscribe challenge. Without this, the script only tests validation reachability.",
    )
    parser.add_argument(
        "--strict-verification-file",
        action="store_true",
        help="Fail if ondc-site-verification.html still contains placeholder content.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tester = SmokeTester(args.base_url, args.timeout, args.subscribe_challenge)
    tester.strict_verification_file = args.strict_verification_file
    try:
        print(f"Testing {tester.base_url}")
        tester.run_foundation_checks()
        tester.run_callback_checks()
        tester.run_mobile_and_admin_checks()
        return tester.print_summary()
    finally:
        tester.close()


if __name__ == "__main__":
    sys.exit(main())
