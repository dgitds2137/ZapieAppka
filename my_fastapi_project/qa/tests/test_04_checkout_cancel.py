#!/usr/bin/env python3
"""
TC-04: create an active checkout then cancel it; cancellation becomes unavailable after.
"""

from qa_test_utils import (
    create_checkout_verification,
    get,
    main_exit,
    make_checkout_items,
    ensure,
    post,
    random_email,
    register,
    login,
)


def run() -> None:
    status, positions = get("/positions")
    ensure(status == 200, f"/positions failed {status}")
    ensure(isinstance(positions, list), "/positions malformed")

    email = random_email("qa-customer-cancel")
    password = "SmokePass123!"

    # Create account and get session.
    register(email=email, password=password, name="QA Cancel")
    customer = login(email=email, password=password)
    token = customer["session_token"]

    items = make_checkout_items(positions, target_total=50.0)
    created = create_checkout_verification(session_token=token, items=items)
    verification_id = created["verification_id"]

    status, body = post(
        "/checkout/cancel",
        {"verification_id": verification_id, "session_token": token},
    )
    ensure(status == 200, f"first cancel failed: {status}, {body}")
    ensure(body.get("verification_id") == verification_id, "cancel response mismatch")

    status, body = post(
        "/checkout/cancel",
        {"verification_id": verification_id, "session_token": token},
    )
    ensure(
        status in (404, 409),
        f"second cancel unexpected status: {status}, body={body}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
