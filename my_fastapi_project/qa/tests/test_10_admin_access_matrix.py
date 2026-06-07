#!/usr/bin/env python3
"""
TC-10: admin endpoint auth matrix for customer/employee/admin.
"""

from qa_test_utils import ensure, get, main_exit, random_email, register, login, require_role_token


def run() -> None:
    status, body = get("/admin/dashboard")
    ensure(status == 401, f"/admin/dashboard without creds: {status}, {body}")

    email = random_email("qa-user-admin-matrix")
    password = "SmokePass123!"
    register(email=email, password=password, name="QA Matrix")
    customer = login(email=email, password=password)

    status, body = get(
        "/admin/dashboard",
        {"session_token": customer["session_token"], "user_email": email},
    )
    ensure(status == 403, f"/admin/dashboard with user role should be forbidden: {status}, {body}")

    employee_email, employee_token = require_role_token("EMPLOYEE")
    status, body = get(
        "/admin/dashboard",
        {"session_token": employee_token, "user_email": employee_email},
    )
    ensure(status == 200, f"/admin/dashboard for employee failed: {status}, {body}")

    driver_email, driver_token = require_role_token("DRIVER")
    status, body = get(
        "/admin/staff-presence",
        {"session_token": driver_token, "user_email": driver_email},
    )
    ensure(
        status == 403,
        f"/admin/staff-presence for driver should be forbidden: {status}, {body}",
    )
    ensure(
        isinstance(body, dict),
        f"/admin/staff-presence malformed: {body}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
