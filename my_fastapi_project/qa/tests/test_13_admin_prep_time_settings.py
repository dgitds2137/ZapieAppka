#!/usr/bin/env python3
"""
TC-13: prep time settings are editable by admin, readable by staff/admin panel users.
"""

from urllib.parse import quote

from qa_test_utils import ensure, get, main_exit, patch, require_role_token


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, prep_settings = get(
        "/admin/prep-time-settings",
        {"session_token": employee_token, "user_email": employee_email},
    )
    ensure(status == 200, f"employee preptime read -> {status}, {prep_settings}")
    ensure(isinstance(prep_settings, list) and prep_settings, f"prep-time settings empty or malformed: {prep_settings}")

    status, body = get(
        "/admin/prep-time-settings",
        {"session_token": "00000000", "user_email": "nobody@zapieapp.pl"},
    )
    ensure(status in (401, 403), f"invalid token should fail: {status}, {body}")

    first = prep_settings[0]
    group_key = first.get("group_key")
    original_minutes = int(first.get("minutes"))
    ensure(group_key, f"group setting missing key: {first}")

    updated_minutes = max(1, original_minutes + 1)
    encoded_group = quote(str(group_key))

    status, updated = patch(
        f"/admin/prep-time-settings/{encoded_group}",
        {
            "minutes": updated_minutes,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin prep-time patch -> {status}, {updated}")
    ensure(updated.get("minutes") == updated_minutes, f"wrong updated minutes: {updated}")
    ensure(updated.get("group_key") == group_key, f"group key changed: {updated}")

    status, restored = patch(
        f"/admin/prep-time-settings/{encoded_group}",
        {
            "minutes": original_minutes,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin prep-time restore -> {status}, {restored}")
    ensure(restored.get("minutes") == original_minutes, f"restore failed: {restored}")

    status, employee_updated = patch(
        f"/admin/prep-time-settings/{encoded_group}",
        {
            "minutes": updated_minutes,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(status == 200, f"employee patch prep-time should be allowed in current backend: {status}, {employee_updated}")
    ensure(employee_updated.get("minutes") == updated_minutes, f"wrong updated minutes from employee: {employee_updated}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
