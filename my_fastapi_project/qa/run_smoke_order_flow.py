#!/usr/bin/env python3
"""
Smoke-like E2E test runner for the most important user journey:
customer -> employee -> driver -> customer.

Usage:
  python run_smoke_order_flow.py

Environment variables:
  BASE_URL (required)
  EMPLOYEE_EMAIL / EMPLOYEE_PASSWORD
  DRIVER_EMAIL / DRIVER_PASSWORD
"""

from __future__ import annotations

import base64
import json
import os
import sys
import time
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class TestFailure(Exception):
    pass


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise TestFailure(f"Missing required env variable: {name}")
    return value


def _to_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _encode_form(data: dict[str, Any]) -> bytes:
    if isinstance(data, dict):
        return urlencode(data, doseq=True).encode("utf-8")
    return urlencode({}, doseq=True).encode("utf-8")


def _request_json(
    method: str,
    url: str,
    json_body: dict[str, Any] | None = None,
    form_body: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    headers: dict[str, str] = {}
    if json_body is not None:
        payload = json.dumps(json_body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif form_body is not None:
        payload = _encode_form(form_body)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    else:
        payload = b""

    req = Request(url, data=payload, method=method, headers=headers)
    try:
        with urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            body = json.loads(raw) if raw else None
            return resp.status, body
    except Exception as exc:  # pragma: no cover - network dependent
        if hasattr(exc, "code") and hasattr(exc, "read"):
            raw = exc.read().decode("utf-8", errors="ignore")
            body = None
            try:
                body = json.loads(raw) if raw else None
            except Exception:
                body = raw
            return int(getattr(exc, "code", 500)), body
        raise TestFailure(f"HTTP request failed: {url} -> {exc}") from exc


def _post(base_url: str, path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return _request_json("POST", f"{base_url.rstrip('/')}{path}", json_body=payload)


def _post_form(base_url: str, path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return _request_json("POST", f"{base_url.rstrip('/')}{path}", form_body=payload)


def _patch(base_url: str, path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return _request_json("PATCH", f"{base_url.rstrip('/')}{path}", json_body=payload)


def _get(base_url: str, path: str, params: dict[str, Any] | None = None) -> tuple[int, Any]:
    query = ""
    if params:
        query = "?" + urlencode(params, doseq=True)
    return _request_json("GET", f"{base_url.rstrip('/')}{path}{query}")


def _ensure(cond: bool, message: str) -> None:
    if not cond:
        raise TestFailure(message)


def _find_order_id_by_verification(dashboard_payload: dict[str, Any], verification_id: str) -> int | None:
    if not isinstance(dashboard_payload, dict):
        return None

    for key in (
        "in_progress_orders",
        "pending_orders",
        "closed_orders",
        "my_taken_orders",
    ):
        rows = dashboard_payload.get(key) or []
        for row in rows:
            if not isinstance(row, dict):
                continue
            if row.get("verification_id") == verification_id:
                order_id = row.get("checkout_order_id")
                if isinstance(order_id, int):
                    return order_id
    return None


def _login_or_register_customer(base_url: str) -> dict[str, Any]:
    email = f"smoke-customer-{int(time.time())}@example.com"
    password = "SmokePass123!"
    password_b64 = base64.b64encode(password.encode("utf-8")).decode("utf-8")

    _, reg_body = _post_form(
        base_url,
        "/register",
        {
            "email": email,
            "password": password_b64,
            "name": "Smoke Customer",
            "phone": "123456789",
        },
    )

    if not isinstance(reg_body, dict) or not reg_body.get("session_token"):
        raise TestFailure("Register failed or did not return session_token.")
    reg_body["email"] = email
    reg_body["password"] = password
    return reg_body


def _login(
    base_url: str,
    email: str,
    password: str,
) -> str:
    pwd_b64 = base64.b64encode(password.encode("utf-8")).decode("utf-8")
    status, body = _post_form(
        base_url,
        "/login",
        {
            "email": email,
            "password": pwd_b64,
        },
    )
    _ensure(status in (200, 201), f"Login failed for {email}: status={status}, body={body}")
    _ensure(
        isinstance(body, dict) and body.get("session_token"),
        f"Login response missing session_token for {email}. Body: {body}",
    )
    return body["session_token"]


def _create_checkout(base_url: str, session_token: str) -> dict[str, Any]:
    status, positions = _get(base_url, "/positions")
    _ensure(status == 200 and isinstance(positions, list) and positions, "/positions is not returning menu items")
    sorted_positions = sorted(
        [
            pos
            for pos in positions
            if isinstance(pos, dict) and pos.get("is_active") is not False
        ],
        key=lambda item: (_to_float(item.get("price")), int(item.get("position_id") or 0)),
        reverse=True,
    )
    _ensure(sorted_positions, "No active positions found in /positions")

    required_total = 50.0
    items = []
    total = 0.0
    cart_entry_id = 1

    for pos in sorted_positions:
        price = _to_float(pos.get("price"))
        if price <= 0:
            continue
        items.append(
            {
                "cart_entry_id": cart_entry_id,
                "position_id": int(pos.get("position_id") or 0),
                "name": pos.get("name") or "Test position",
                "description": pos.get("description"),
                "photo_url": pos.get("photo_url"),
                "calories": pos.get("calories"),
                "price": price,
            },
        )
        cart_entry_id += 1
        total += price
        if total >= required_total:
            break

    if total < required_total and sorted_positions:
        # duplicate highest priced item to reach minimum delivery threshold
        while total < required_total:
            top = sorted_positions[0]
            top_price = _to_float(top.get("price"))
            if top_price <= 0:
                break
            items.append(
                {
                    "cart_entry_id": cart_entry_id,
                    "position_id": int(top.get("position_id") or 0),
                    "name": top.get("name") or "Test position",
                    "description": top.get("description"),
                    "photo_url": top.get("photo_url"),
                    "calories": top.get("calories"),
                    "price": top_price,
                },
            )
            cart_entry_id += 1
            total += top_price
            if cart_entry_id > 30:
                break

    verification_payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "currency": "PLN",
        "subtotal_amount": total,
        "total_amount": total,
        "redeemed_points": 0,
        "redeemed_amount": 0,
        "eta_minutes": 30,
        "payment_method": "BLIK",
        "fulfillment_method": "dostawa",
        "fulfillment_option_index": 0,
        "address_option_index": 0,
        "address": {
            "title": "Testowa ul. Smocza",
            "subtitle": "ul. Smocza 1, Warszawa",
            "eta_label": "~30 min",
        },
        "items": items,
        "session_token": session_token,
        "notes": "automated smoke",
    }
    status, body = _request_json("POST", f"{base_url.rstrip('/')}/checkout/verification", json_body=verification_payload)
    _ensure(
        status in (200, 201) and isinstance(body, dict),
        f"/checkout/verification failed: status={status}, body={body}",
    )
    return body


def _run() -> None:
    base_url = _require_env("BASE_URL")
    employee_email = _require_env("EMPLOYEE_EMAIL")
    employee_password = _require_env("EMPLOYEE_PASSWORD")
    driver_email = _require_env("DRIVER_EMAIL")
    driver_password = _require_env("DRIVER_PASSWORD")
    print(f"[SMOKE] base url: {base_url}")

    status, health = _get(base_url, "/health")
    _ensure(status == 200, f"/health failed with status={status}, body={health}")

    status, health_db = _get(base_url, "/health/db")
    _ensure(status == 200, f"/health/db failed with status={status}, body={health_db}")

    print(f"[TC1] customer register + create checkout on {base_url}")
    customer = _login_or_register_customer(base_url)
    cust_token = customer["session_token"]
    customer_email = customer["email"]
    checkout = _create_checkout(base_url, cust_token)

    verification_id = checkout.get("verification_id")
    _ensure(verification_id, "verification_id missing in checkout verification response")
    _ensure(
        checkout.get("processing_status") == "unassigned",
        f"Unexpected processing_status: {checkout.get('processing_status')}",
    )

    status, active = _get(base_url, "/checkout/active", {"session_token": cust_token})
    _ensure(status == 200, f"/checkout/active failed with status={status}")
    _ensure(
        not active or active.get("verification_id") == verification_id,
        "Active checkout does not match created verification_id",
    )

    print("[TC1] OK")

    print("[TC2] employee/operator takes and progresses order")
    operator_token = _login(base_url, employee_email, employee_password)
    status, dashboard = _get(base_url, "/admin/dashboard", {"session_token": operator_token})
    _ensure(status == 200, f"/admin/dashboard failed: status={status}, body={dashboard}")

    order_id = _find_order_id_by_verification(dashboard, verification_id)
    _ensure(order_id is not None, "Could not map verification_id to checkout_order_id in dashboard payload")
    print(f"[TC2] mapped verification_id {verification_id} -> checkout_order_id {order_id}")

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": operator_token,
            "verification_stage": "",
            "user_email": employee_email,
        },
    )
    _ensure(
        status == 200,
        f"Assign failed: status={status}, body={admin_body}",
    )
    _ensure(admin_body.get("checkout_order_id") == order_id, "assign response order id mismatch")

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "in_oven",
            "session_token": operator_token,
        },
    )
    _ensure(
        status == 200,
        f"Set in_oven failed: status={status}, body={admin_body}",
    )
    _ensure(admin_body.get("verification_stage") in {"in_oven", "assigned"}, "in_oven stage not applied")

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "ready_for_delivery",
            "session_token": operator_token,
        },
    )
    _ensure(
        status == 200,
        f"Set ready_for_delivery failed: status={status}, body={admin_body}",
    )
    _ensure(
        admin_body.get("verification_stage") == "ready_for_delivery"
        or admin_body.get("verification_stage") == "accepted",
        "ready_for_delivery stage not present",
    )

    print("[TC2] OK")

    print("[TC3] driver takes delivery and completes, then customer confirms")
    driver_token = _login(base_url, driver_email, driver_password)

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": driver_token,
        },
    )
    _ensure(
        status == 200,
        f"Driver assign failed: status={status}, body={admin_body}",
    )

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "on_the_way",
            "session_token": driver_token,
        },
    )
    _ensure(
        status == 200,
        f"Driver on_the_way failed: status={status}, body={admin_body}",
    )

    status, admin_body = _patch(
        base_url,
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "completed",
            "session_token": driver_token,
        },
    )
    _ensure(
        status == 200,
        f"Driver complete failed: status={status}, body={admin_body}",
    )
    _ensure(
        admin_body.get("processing_status") == "completed",
        "Order was not marked as completed",
    )

    status, active_after = _get(
        base_url,
        "/checkout/active",
        {"session_token": cust_token},
    )
    _ensure(
        status == 200,
        f"checkout/active after completion failed: status={status}",
    )
    _ensure(
        active_after is None or active_after.get("verification_id") == verification_id,
        "Active order changed unexpectedly after driver completion",
    )

    confirm_payload = {
        "received": True,
        "session_token": cust_token,
    }
    status, confirm = _post(base_url, "/checkout/confirm-receipt", confirm_payload)
    _ensure(status in (200, 201), f"checkout/confirm-receipt failed: status={status}, body={confirm}")
    print(f"[TC3] customer session={customer_email} / checkout completed")

    print("SMOKE_OK")


if __name__ == "__main__":
    try:
        _run()
    except TestFailure as exc:
        print(f"SMOKE_FAIL: {exc}")
        sys.exit(1)
