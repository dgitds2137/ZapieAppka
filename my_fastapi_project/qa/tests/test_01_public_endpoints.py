#!/usr/bin/env python3
"""
TC-01: public smoke endpoints are reachable and return expected shapes.
"""

from qa_test_utils import get, require_env, ensure, main_exit


def run() -> None:
    require_env("BASE_URL")

    status, body = get("/health")
    ensure(status == 200, f"/health -> {status}")
    ensure(isinstance(body, dict) and body.get("status") == "ok", f"/health malformed: {body}")

    status, body = get("/health/db")
    ensure(status == 200, f"/health/db -> {status}")
    ensure(isinstance(body, dict) and body.get("database") == "ok", f"/health/db malformed: {body}")

    for path in [
        "/opening-hours",
        "/checkout/udka-availability",
        "/checkout/delivery-estimate",
        "/checkout/active",
        "/checkout/history",
    ]:
        status, _ = get(path)
        ensure(status == 200, f"{path} -> {status}")

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list), "/positions is not a list")
    ensure(len(positions) > 0, "/positions empty")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
