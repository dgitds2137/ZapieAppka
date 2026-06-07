#!/usr/bin/env python3
"""
TC-20: admin-only kitchen ETA override endpoint.
"""

from qa_test_utils import ensure, main_exit, require_role_token, patch


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, body = patch(
        "/admin/catalog/kitchen-eta",
        {
            "minutes": 10,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(
        status == 403,
        f"employee should be forbidden for kitchen eta override: {status}, {body}",
    )

    status, body = patch(
        "/admin/catalog/kitchen-eta",
        {
            "minutes": 20,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin update failed: {status}, {body}")
    ensure(
        isinstance(body, dict)
        and body.get("kitchen_eta_override_minutes") == 20,
        f"admin override response malformed: {body}",
    )

    status, body = patch(
        "/admin/catalog/kitchen-eta",
        {
            "minutes": 15,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 400, f"invalid override should be rejected: {status}, {body}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
