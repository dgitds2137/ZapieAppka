#!/usr/bin/env python3
"""
TC-18: delivery reaches awaiting_receipt_confirmation after driver completion.
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


def run() -> None:
    customer_email = random_email("qa-delivery-driver")
    password = "SmokePass123!"
    register(email=customer_email, password=password, name="QA Delivery Driver")
    customer = login(customer_email, password)
    customer_token = customer["session_token"]
    customer_email = customer["email"]

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}, {positions}")
    ensure(isinstance(positions, list) and positions, "/positions empty")

    items = make_checkout_items(positions, target_total=75.0)
    created = create_checkout_verification(session_token=customer_token, items=items, fulfillment_method="dostawa")
    order_id = int(created["saved_order_id"])
    verification_id = created["verification_id"]

    employee_email, employee_token = require_role_token("EMPLOYEE")
    driver_email, driver_token = require_role_token("DRIVER")

    status, assigned = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"employee assign failed: {status}, {assigned}")

    status, ready = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "ready_for_delivery",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"ready_for_delivery failed: {status}, {ready}")

    status, in_transit = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver take failed: {status}, {in_transit}")
    ensure(
        in_transit.get("verification_stage") in {"on_the_way", "ready_for_delivery"},
        f"driver assign stage unexpected: {in_transit}",
    )

    status, completed_by_driver = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "completed",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver complete failed: {status}, {completed_by_driver}")
    ensure(
        completed_by_driver.get("processing_status") == "completed",
        f"completion response unexpected: {completed_by_driver}",
    )
    ensure(
        completed_by_driver.get("verification_id") == verification_id,
        f"wrong order returned: {completed_by_driver}",
    )

    status, driver_dashboard = get(
        "/admin/dashboard",
        {"session_token": driver_token, "user_email": driver_email},
    )
    ensure(status == 200, f"/admin/dashboard driver -> {status}, {driver_dashboard}")
    ensure(isinstance(driver_dashboard, dict), f"driver dashboard malformed: {driver_dashboard}")
    closed_orders = driver_dashboard.get("closed_orders") or []
    ensure(
        any(
            isinstance(order, dict) and int(order.get("checkout_order_id")) == order_id
            for order in closed_orders
        ),
        f"delivery order not present in driver closed_orders: {driver_dashboard}",
    )

    status, active = get(
        "/checkout/active",
        {"session_token": customer_token, "email": customer_email},
    )
    ensure(status == 200, f"/checkout/active customer -> {status}, {active}")
    ensure(
        isinstance(active, dict) and active.get("verification_id") == verification_id,
        f"active checkout missing after driver completion: {active}",
    )
    ensure(
        active.get("verification_stage") == "awaiting_receipt_confirmation",
        f"unexpected verification_stage after driver completion: {active}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
