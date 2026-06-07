#!/usr/bin/env python3
"""
TC-09: admin-only catalog update endpoints with role guard checks.
"""

from qa_test_utils import ensure, main_exit, require_role_token, patch


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, body = patch(
        "/admin/catalog/delivery-minimum",
        {
            "amount": 25.0,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 403, f"employee update should be forbidden: {status}, {body}")

    status, body = patch(
        "/admin/catalog/delivery-minimum",
        {
            "amount": 25.0,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin update failed: {status}, {body}")
    ensure(
        isinstance(body, dict) and body.get("delivery_minimum_amount") == 25.0,
        f"admin response malformed: {body}",
    )

    status, body = patch(
        "/admin/catalog/delivery-radius",
        {
            "radius_km": 8.0,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin radius update failed: {status}, {body}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
