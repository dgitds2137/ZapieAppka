#!/usr/bin/env python3
"""
TC-11: staff completes an order and it appears in checkout history.
"""

from qa_test_utils import (
    create_checkout_verification,
    ensure,
    get,
    main_exit,
    make_checkout_items,
    patch,
    random_email,
    register,
    login,
    require_role_token,
)
import time


def run() -> None:
    email = random_email("qa-complete")
    password = "SmokePass123!"
    register(email=email, password=password, name="QA Complete")
    customer = login(email=email, password=password)
    customer_token = customer["session_token"]
    customer_email = customer["email"]

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}, {positions}")
    ensure(isinstance(positions, list) and positions, "/positions is empty")

    items = make_checkout_items(positions, target_total=60.0)
    created = create_checkout_verification(session_token=customer_token, items=items)
    verification_id = created["verification_id"]
    checkout_order_id = int(created["saved_order_id"])

    employee_email, employee_token = require_role_token("EMPLOYEE")

    def order_on_panel(board: dict) -> bool:
        for bucket_name in ("pending_orders", "in_progress_orders", "my_taken_orders"):
            for order in board.get(bucket_name) or []:
                if (
                    isinstance(order, dict)
                    and order.get("checkout_order_id") is not None
                    and int(order.get("checkout_order_id")) == checkout_order_id
                ):
                    return True
        return False

    status, dashboard = get(
        "/admin/dashboard",
        {"session_token": employee_token, "user_email": employee_email},
    )
    ensure(status == 200, f"/admin/dashboard failed: {status}, {dashboard}")

    retries_left = 6
    while retries_left > 0 and not order_on_panel(dashboard):
        time.sleep(1)
        status, dashboard = get(
            "/admin/dashboard",
            {"session_token": employee_token, "user_email": employee_email},
        )
        ensure(status == 200, f"/admin/dashboard retry failed: {status}, {dashboard}")
        retries_left -= 1

    ensure(order_on_panel(dashboard), f"checkout order not visible on employee dashboard: {checkout_order_id}")

    status, assigned = patch(
        f"/admin/orders/{checkout_order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"assign failed: {status}, {assigned}")
    ensure(
        str(assigned.get("checkout_order_id")) == str(checkout_order_id),
        f"wrong order returned after assign: {assigned}",
    )

    status, completed = patch(
        f"/admin/orders/{checkout_order_id}/processing-status",
        {
            "processing_status": "completed",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"complete failed: {status}, {completed}")
    ensure(
        str(completed.get("checkout_order_id")) == str(checkout_order_id),
        f"wrong order returned after complete: {completed}",
    )

    status, history = get(
        "/checkout/history",
        {
            "session_token": customer_token,
            "user_email": customer_email,
            "page": 1,
            "page_size": 10,
        },
    )
    ensure(status == 200, f"/checkout/history failed: {status}, {history}")
    ensure(isinstance(history, dict), "/checkout/history malformed")
    orders = history.get("orders", [])
    ensure(any(
        isinstance(order, dict) and order.get("verification_id") == verification_id
        for order in orders
    ), f"completed order not found in history: {history}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
