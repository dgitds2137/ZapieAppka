#!/usr/bin/env python3
"""
TC-14: checkout cancel should protect auth and allow cancellation before staff accepts order.
"""

from qa_test_utils import (
    create_checkout_verification,
    ensure,
    get,
    main_exit,
    make_checkout_items,
    post,
    random_email,
    register,
    login,
)


def run() -> None:
    status, body = post("/checkout/cancel", {})
    ensure(status == 401, f"anon cancel should be unauthorized: {status}, {body}")

    email = random_email("qa-cancel")
    password = "SmokePass123!"
    register(email=email, password=password, name="QA Cancel")
    customer = login(email=email, password=password)
    customer_token = customer["session_token"]
    customer_email = customer["email"]

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list) and positions, "/positions empty")

    items = make_checkout_items(positions, target_total=55.0)
    created = create_checkout_verification(session_token=customer_token, items=items)
    verification_id = created.get("verification_id")
    ensure(verification_id, f"invalid verification id: {created}")

    status, body = post(
        "/checkout/cancel",
        {
            "session_token": customer_token,
            "user_email": customer_email,
            "verification_id": "wrong-verification-id",
        },
    )
    ensure(status == 409, f"wrong verification_id should be rejected: {status}, {body}")

    status, body = post(
        "/checkout/cancel",
        {
            "session_token": customer_token,
            "user_email": customer_email,
            "verification_id": verification_id,
        },
    )
    ensure(status == 200, f"cancel failed: {status}, {body}")
    ensure(
        isinstance(body, dict) and body.get("status") == "cancelled",
        f"cancel response malformed: {body}",
    )

    status, active = get("/checkout/active", {"session_token": customer_token})
    ensure(status == 200, f"/checkout/active after cancel -> {status}, {active}")
    if isinstance(active, dict):
        ensure(
            active.get("verification_id") != verification_id,
            f"cancelled order still exposed in active: {active}",
        )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
