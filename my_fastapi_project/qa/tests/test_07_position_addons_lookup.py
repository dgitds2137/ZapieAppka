#!/usr/bin/env python3
"""
TC-07: verify position addons endpoint and 404 handling for unknown position.
"""

from qa_test_utils import get, ensure, main_exit


def _to_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def run() -> None:
    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list) and positions, "/positions empty or malformed")

    position_id = _to_int(positions[0].get("position_id"))
    ensure(position_id is not None, f"/positions first item invalid: {positions[0]}")

    status, addons = get(f"/position/{position_id}/addons")
    ensure(status == 200, f"/position/{position_id}/addons -> {status}, {addons}")
    ensure(isinstance(addons, list), "/position addons malformed")
    if addons:
        sample = addons[0]
        ensure(isinstance(sample, dict), f"addon malformed: {sample}")
        ensure("name" in sample, f"addon missing name: {sample}")
        ensure("price" in sample, f"addon missing price: {sample}")

    status, body = get("/position/99999999/addons")
    ensure(status == 404, f"/position/{99999999}/addons unexpected status: {status}, {body}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
