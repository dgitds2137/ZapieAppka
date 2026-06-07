#!/usr/bin/env python3
"""
TC-17: closed orders history is admin-only and returns paged payload.
"""

from qa_test_utils import ensure, get, main_exit, require_role_token


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, body = get("/admin/orders/history", {"session_token": employee_token, "user_email": employee_email})
    ensure(status == 200, f"employee should be able to access assigned closed order history: {status}, {body}")
    ensure(isinstance(body, dict), f"employee orders history malformed: {body}")
    ensure("orders" in body and isinstance(body["orders"], list), f"employee orders history malformed orders: {body}")

    status, body = get("/admin/orders/history", {"session_token": admin_token, "user_email": admin_email})
    ensure(status == 200, f"admin closed-order history failed: {status}, {body}")
    ensure(isinstance(body, dict), f"admin orders history malformed: {body}")
    ensure("orders" in body and isinstance(body["orders"], list), f"history.orders missing list: {body}")
    ensure(
        "total_count" in body and isinstance(body["total_count"], int),
        f"history.total_count missing: {body}",
    )

    status, second = get(
        "/admin/orders/history",
        {
            "session_token": admin_token,
            "user_email": admin_email,
            "page": 1,
            "page_size": 3,
            "today_only": False,
        },
    )
    ensure(status == 200, f"admin history pagination failed: {status}, {second}")
    ensure(isinstance(second, dict), f"admin history pagination malformed: {second}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
