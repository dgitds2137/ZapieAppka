#!/usr/bin/env python3
"""
TC-19: customer confirms delivery and checkout no longer remains active.
"""

from qa_test_utils import (
    create_checkout_verification,
    ensure,
    get,
    main_exit,
    make_checkout_items,
    post,
    patch,
    random_email,
    register,
    login,
    require_role_token,
)


def run() -> None:
    customer_email = random_email("qa-delivery-confirm")
    password = "SmokePass123!"
    register(email=customer_email, password=password, name="QA Delivery Confirm")
    customer = login(customer_email, password)
    customer_token = customer["session_token"]
    customer_email = customer["email"]

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list) and positions, "/positions empty")

    items = make_checkout_items(positions, target_total=80.0)
    created = create_checkout_verification(
        session_token=customer_token,
        items=items,
        fulfillment_method="dostawa",
    )
    order_id = int(created["saved_order_id"])
    verification_id = created["verification_id"]

    employee_email, employee_token = require_role_token("EMPLOYEE")
    driver_email, driver_token = require_role_token("DRIVER")

    status, _ = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"employee assign failed: {status}")

    status, _ = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "ready_for_delivery",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"ready_for_delivery failed: {status}")

    status, _ = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver in_transit failed: {status}")

    status, _ = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "completed",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver complete failed: {status}, {order_id}")

    status, confirm = post(
        "/checkout/confirm-receipt",
        {
            "received": True,
            "session_token": customer_token,
            "user_email": customer_email,
        },
    )
    ensure(status == 200, f"receipt confirmation failed: {status}, {confirm}")
    ensure(
        isinstance(confirm, dict) and confirm.get("verification_id") == verification_id,
        f"confirm response malformed: {confirm}",
    )
    ensure(
        confirm.get("verification_stage") == "delivered_confirmed",
        f"unexpected verification_stage after confirm: {confirm}",
    )
    ensure(
        confirm.get("status") == "completed",
        f"unexpected status after confirm: {confirm}",
    )

    status, active = get(
        "/checkout/active",
        {"session_token": customer_token, "email": customer_email},
    )
    ensure(status == 200, f"/checkout/active -> {status}, {active}")
    ensure(
        active is None or active.get("verification_id") != verification_id,
        f"order should not stay active after delivery confirmation: {active}",
    )

    status, history = get(
        "/checkout/history",
        {
            "session_token": customer_token,
            "user_email": customer_email,
            "page": 1,
            "page_size": 20,
        },
    )
    ensure(status == 200, f"/checkout/history -> {status}, {history}")
    ensure(isinstance(history, dict), f"/checkout/history malformed: {history}")
    ensure(
        any(
            isinstance(order, dict) and order.get("verification_id") == verification_id
            for order in history.get("orders", [])
        ),
        f"confirmed order missing in history: {history}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
