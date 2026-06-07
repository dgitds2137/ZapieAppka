#!/usr/bin/env python3
"""
TC-15: opening hours endpoint validation and admin-only write access.
"""

from qa_test_utils import ensure, get, main_exit, patch, require_role_token


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, catalog = get("/admin/catalog", {"session_token": admin_token, "user_email": admin_email})
    ensure(status == 200, f"/admin/catalog -> {status}, {catalog}")
    ensure(isinstance(catalog, dict), f"/admin/catalog malformed: {catalog}")
    current = catalog.get("opening_hours") or {}
    open_time = current.get("open_time")
    close_time = current.get("close_time")
    ensure(isinstance(open_time, str) and isinstance(close_time, str), f"opening hours malformed: {current}")

    status, invalid = patch(
        "/admin/catalog/opening-hours",
        {
            "open_time": open_time,
            "close_time": open_time,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 400, f"invalid opening hours should be rejected: {status}, {invalid}")

    status, unchanged = patch(
        "/admin/catalog/opening-hours",
        {
            "open_time": open_time,
            "close_time": close_time,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"valid opening-hours update failed: {status}, {unchanged}")
    ensure(
        unchanged.get("opening_hours", {}).get("open_time") == open_time,
        f"opening_hours changed unexpectedly: {unchanged}",
    )

    status, forbidden = patch(
        "/admin/catalog/opening-hours",
        {
            "open_time": open_time,
            "close_time": close_time,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 403, f"employee should be forbidden to update hours: {status}, {forbidden}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
