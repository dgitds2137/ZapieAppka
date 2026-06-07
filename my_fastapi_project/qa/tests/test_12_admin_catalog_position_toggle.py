#!/usr/bin/env python3
"""
TC-12: admin can toggle menu position availability, employee cannot.
"""

from qa_test_utils import ensure, get, main_exit, patch, require_role_token


def run() -> None:
    admin_email, admin_token = require_role_token("ADMIN")
    employee_email, employee_token = require_role_token("EMPLOYEE")

    status, catalog = get(
        "/admin/catalog",
        {"session_token": admin_token, "user_email": admin_email},
    )
    ensure(status == 200, f"/admin/catalog as admin -> {status}, {catalog}")
    ensure(
        isinstance(catalog, dict) and isinstance(catalog.get("positions"), list),
        f"/admin/catalog malformed: {catalog}",
    )
    ensure(catalog["positions"], "/admin/catalog positions list empty")

    first = catalog["positions"][0]
    position_id = int(first.get("position_id"))
    original_active = bool(first.get("is_active"))

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "is_active": not original_active,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin toggle position -> {status}, {body}")
    ensure(
        body.get("is_active") == (not original_active),
        f"position not toggled: {body}",
    )
    ensure(
        body.get("position_id") == position_id,
        f"wrong position returned: {body}",
    )

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "is_active": original_active,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin restore position -> {status}, {body}")
    ensure(
        body.get("is_active") == original_active,
        f"position not restored: {body}",
    )

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "is_active": original_active,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(
        status == 403,
        f"employee should be forbidden: {status}, {body}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
