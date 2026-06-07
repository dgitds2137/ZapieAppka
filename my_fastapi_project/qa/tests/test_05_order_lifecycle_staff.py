#!/usr/bin/env python3
"""
TC-05: staff-assisted flow: employee takes order, marks ready for delivery, driver delivers, customer confirms.
"""

from qa_test_utils import (
    create_checkout_verification,
    ensure,
    find_order_id,
    get,
    main_exit,
    make_checkout_items,
    patch,
    post,
    random_email,
    register,
    login,
    require_role_token,
)


def run() -> None:
    customer_email = random_email("qa-customer-flow")
    password = "SmokePass123!"
    register(email=customer_email, password=password, name="QA Flow")
    customer = login(customer_email, password)
    customer_token = customer["session_token"]

    status, positions = get("/positions")
    ensure(status == 200 and isinstance(positions, list), "/positions failed")
    items = make_checkout_items(positions, target_total=50.0)
    created = create_checkout_verification(session_token=customer_token, items=items)
    verification_id = created["verification_id"]

    employee_email, employee_token = require_role_token("EMPLOYEE")
    driver_email, driver_token = require_role_token("DRIVER")

    status, dashboard = get(
        "/admin/dashboard",
        {"session_token": employee_token, "user_email": employee_email},
    )
    ensure(status == 200, f"/admin/dashboard failed: {status}, {dashboard}")
    order_id = find_order_id(dashboard, verification_id)
    ensure(order_id is not None, f"order not present on dashboard for {verification_id}")

    status, body = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"employee assign failed: {status}, {body}")

    status, body = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "ready_for_delivery",
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"ready_for_delivery failed: {status}, {body}")

    status, body = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver take failed: {status}, {body}")

    status, body = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "assigned",
            "verification_stage": "on_the_way",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver on_the_way failed: {status}, {body}")

    status, body = patch(
        f"/admin/orders/{order_id}/processing-status",
        {
            "processing_status": "completed",
            "session_token": driver_token,
            "user_email": driver_email,
        },
    )
    ensure(status == 200, f"driver complete failed: {status}, {body}")

    status, active = get("/checkout/active", {"session_token": customer_token})
    ensure(status == 200, f"/checkout/active failed: {status}")

    status, confirmed = post(
        "/checkout/confirm-receipt",
        {"received": True, "session_token": customer_token},
    )
    ensure(
        status in (200, 201),
        f"confirm receipt failed: {status}, {confirmed}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
