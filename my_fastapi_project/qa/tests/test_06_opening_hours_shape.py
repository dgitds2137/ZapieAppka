#!/usr/bin/env python3
"""
TC-06: verify opening-hours payload and time fields contract.
"""

import re

from qa_test_utils import get, ensure, require_env, main_exit


TIME_RE = re.compile(r"^\d{1,2}:\d{2}$")


def run() -> None:
    require_env("BASE_URL")

    status, payload = get("/opening-hours")
    ensure(status == 200, f"/opening-hours -> {status}, {payload}")
    ensure(isinstance(payload, dict), f"/opening-hours malformed: {payload}")
    for field in ("open_time", "close_time", "formatted_range", "is_open_now"):
        ensure(field in payload, f"/opening-hours missing {field}")
    ensure(
        isinstance(payload["open_time"], str) and TIME_RE.match(payload["open_time"]),
        f"/opening-hours open_time bad: {payload['open_time']}",
    )
    ensure(
        isinstance(payload["close_time"], str) and TIME_RE.match(payload["close_time"]),
        f"/opening-hours close_time bad: {payload['close_time']}",
    )
    ensure(
        isinstance(payload["formatted_range"], str) and "-" in payload["formatted_range"],
        f"/opening-hours formatted_range bad: {payload['formatted_range']}",
    )
    ensure(
        isinstance(payload["is_open_now"], bool),
        f"/opening-hours is_open_now bad: {payload['is_open_now']}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
