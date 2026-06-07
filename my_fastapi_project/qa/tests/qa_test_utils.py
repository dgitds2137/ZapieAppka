#!/usr/bin/env python3
"""
Shared utilities for lightweight API test scripts in QA folder.
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


def require_env(name: str) -> str:
    value = (os.getenv(name) or "").strip()
    if not value:
        raise TestFailure(f"Missing required env var: {name}")
    return value


def base_url() -> str:
    return require_env("BASE_URL")


def b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("utf-8")


def encode_form(payload: dict[str, Any]) -> bytes:
    return urlencode(payload, doseq=True).encode("utf-8")


def request_json(
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
        payload = encode_form(form_body)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    else:
        payload = b""

    req = Request(url, data=payload, method=method, headers=headers)
    try:
        with urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            parsed = json.loads(body) if body else None
            return resp.status, parsed
    except Exception as exc:
        if hasattr(exc, "code") and hasattr(exc, "read"):
            code = int(getattr(exc, "code", 500))
            raw = exc.read().decode("utf-8", errors="ignore")
            try:
                parsed = json.loads(raw) if raw else None
            except Exception:
                parsed = raw
            return code, parsed
        raise TestFailure(f"Request failed: {url} -> {exc}") from exc


def get(path: str, params: dict[str, Any] | None = None) -> tuple[int, Any]:
    query = ""
    if params:
        query = "?" + urlencode(params, doseq=True)
    return request_json("GET", f"{base_url().rstrip('/')}{path}{query}")


def post(path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return request_json("POST", f"{base_url().rstrip('/')}{path}", json_body=payload)


def post_form(path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return request_json("POST", f"{base_url().rstrip('/')}{path}", form_body=payload)


def patch(path: str, payload: dict[str, Any]) -> tuple[int, Any]:
    return request_json("PATCH", f"{base_url().rstrip('/')}{path}", json_body=payload)


def ensure(cond: bool, message: str) -> None:
    if not cond:
        raise TestFailure(message)


def register(email: str, password: str, name: str | None = None) -> dict[str, Any]:
    payload = {
        "email": email,
        "password": b64(password),
        "name": name or "QA User",
        "phone": "123456789",
    }
    status, body = post_form("/register", payload)
    ensure(status in (200, 201), f"Register failed {email}: status={status}, body={body}")
    ensure(isinstance(body, dict) and body.get("session_token"), f"Register response missing token {email}: {body}")
    return body


def login(email: str, password: str) -> dict[str, Any]:
    status, body = post_form(
        "/login",
        {"email": email, "password": b64(password)},
    )
    ensure(status in (200, 201), f"Login failed {email}: status={status}, body={body}")
    ensure(isinstance(body, dict) and body.get("session_token"), f"Login response missing session_token for {email}: {body}")
    return body


def make_checkout_items(positions: list[dict[str, Any]], target_total: float) -> list[dict[str, Any]]:
    available = [
        p for p in positions
        if isinstance(p, dict) and (p.get("is_active") is not False)
    ]
    active = [p for p in available if (p.get("price") or 0) > 0]
    if not active:
        active = [p for p in available if p.get("price") is not None]
    ensure(active, "No menu positions found / no active positions with price.")

    active.sort(key=lambda item: float(item.get("price") or 0), reverse=True)
    result: list[dict[str, Any]] = []
    total = 0.0
    cart_entry_id = 1

    for pos in active:
        price = float(pos.get("price") or 0)
        if price <= 0:
            continue
        result.append(
            {
                "cart_entry_id": cart_entry_id,
                "position_id": int(pos.get("position_id") or 0),
                "name": pos.get("name") or "Item",
                "description": pos.get("description"),
                "photo_url": pos.get("photo_url"),
                "calories": pos.get("calories"),
                "price": price,
            },
        )
        cart_entry_id += 1
        total += price
        if total >= target_total:
            break

    if not result:
        top = active[0]
        price = float(top.get("price") or 0)
        result.append(
            {
                "cart_entry_id": 1,
                "position_id": int(top.get("position_id") or 0),
                "name": top.get("name") or "Item",
                "description": top.get("description"),
                "photo_url": top.get("photo_url"),
                "calories": top.get("calories"),
                "price": price,
            },
        )
        total = price

    while total < target_total and result:
        top = result[0]
        top_price = float(top.get("price") or 0)
        if top_price <= 0:
            break
        result.append(
            {
                "cart_entry_id": cart_entry_id,
                "position_id": top["position_id"],
                "name": top["name"],
                "description": top["description"],
                "photo_url": top["photo_url"],
                "calories": top["calories"],
                "price": top_price,
            },
        )
        cart_entry_id += 1
        total += top_price
        if cart_entry_id > 40:
            break

    return result


def create_checkout_verification(
    session_token: str,
    items: list[dict[str, Any]],
    fulfillment_method: str = "dostawa",
    fulfillment_option_index: int = 0,
    address_option_index: int = 0,
) -> dict[str, Any]:
    payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "currency": "PLN",
        "subtotal_amount": 0,
        "total_amount": 0,
        "redeemed_points": 0,
        "redeemed_amount": 0,
        "eta_minutes": 30,
        "payment_method": "BLIK",
        "fulfillment_method": fulfillment_method,
        "fulfillment_option_index": fulfillment_option_index,
        "address_option_index": address_option_index,
        "address": {
            "title": "Test",
            "subtitle": "ul. Testowa 1",
            "eta_label": "~30 min",
        },
        "items": items,
        "session_token": session_token,
        "notes": "qa test",
    }
    status, body = post("/checkout/verification", payload)
    ensure(status in (200, 201), f"Checkout creation failed: status={status}, body={body}")
    ensure(isinstance(body, dict) and body.get("verification_id"), f"Invalid checkout response: {body}")
    return body


def find_order_id(
    dashboard: dict[str, Any],
    verification_id: str,
) -> int | None:
    if not isinstance(dashboard, dict):
        return None
    for bucket in ("pending_orders", "in_progress_orders", "my_taken_orders", "closed_orders"):
        for item in dashboard.get(bucket, []) or []:
            if (
                isinstance(item, dict)
                and item.get("verification_id") == verification_id
                and item.get("checkout_order_id") is not None
            ):
                return int(item.get("checkout_order_id"))
    return None


def require_role_token(role_env: str) -> tuple[str, str]:
    email = require_env(f"{role_env}_EMAIL")
    password = require_env(f"{role_env}_PASSWORD")
    login_result = login(email, password)
    return email, login_result["session_token"]


def with_context(label: str) -> None:
    print(f"[{label}]")


def run_test(label: str, fn) -> None:
    with_context(label)
    fn()
    print(f"{label}: PASS")


def fail_fast(exc: Exception) -> int:
    print(f"{exc}")
    return 1


def random_email(prefix: str) -> str:
    return f"{prefix}-{int(time.time())}-{int(time.time() * 1000) % 10000}@example.com"


def main_exit(func):
    try:
        func()
        return 0
    except TestFailure as exc:
        return fail_fast(f"FAIL: {exc}")
    except Exception as exc:
        return fail_fast(f"UNHANDLED: {exc}")
