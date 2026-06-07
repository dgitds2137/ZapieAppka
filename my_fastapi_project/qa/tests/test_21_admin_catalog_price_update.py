#!/usr/bin/env python3
"""
TC-21: admin-only catalog price updates.
"""

from qa_test_utils import ensure, get, main_exit, patch, require_role_token


def run() -> None:
    employee_email, employee_token = require_role_token("EMPLOYEE")
    admin_email, admin_token = require_role_token("ADMIN")

    status, catalog = get(
        "/admin/catalog",
        {
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"/admin/catalog as admin -> {status}, {catalog}")
    ensure(isinstance(catalog, dict), f"/admin/catalog malformed: {catalog}")

    positions = catalog.get("positions") or []
    addons = catalog.get("addons") or []
    ensure(bool(positions), f"/admin/catalog positions empty: {catalog}")
    ensure(bool(addons), f"/admin/catalog addons empty: {catalog}")

    position_id = int(positions[0].get("position_id"))
    addon_id = int(addons[0].get("addon_id"))
    original_position_price = positions[0].get("price")
    original_addon_price = addons[0].get("price")

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "price": 12.34,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin position price update failed: {status}, {body}")
    ensure(
        isinstance(body, dict) and float(body.get("price")) == 12.34,
        f"position price mismatch: {body}",
    )
    ensure(
        int(body.get("position_id")) == position_id,
        f"wrong position returned: {body}",
    )

    status, body = patch(
        f"/admin/catalog/addons/{addon_id}",
        {
            "price": 3.21,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(status == 200, f"admin addon price update failed: {status}, {body}")
    ensure(
        isinstance(body, dict) and float(body.get("price")) == 3.21,
        f"addon price mismatch: {body}",
    )
    ensure(
        int(body.get("addon_id")) == addon_id,
        f"wrong addon returned: {body}",
    )

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "price": -1.00,
            "session_token": admin_token,
            "user_email": admin_email,
        },
    )
    ensure(
        status == 400,
        f"negative price should be rejected: {status}, {body}",
    )

    status, body = patch(
        f"/admin/catalog/positions/{position_id}",
        {
            "is_active": True,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(
        status == 403,
        f"employee should be forbidden on position endpoint: {status}, {body}",
    )

    status, body = patch(
        f"/admin/catalog/addons/{addon_id}",
        {
            "price": 4.20,
            "session_token": employee_token,
            "user_email": employee_email,
        },
    )
    ensure(
        status == 403,
        f"employee should be forbidden on addon endpoint: {status}, {body}",
    )

    if original_position_price is not None:
        patch(
            f"/admin/catalog/positions/{position_id}",
            {
                "price": float(original_position_price),
                "session_token": admin_token,
                "user_email": admin_email,
            },
        )
    if original_addon_price is not None:
        patch(
            f"/admin/catalog/addons/{addon_id}",
            {
                "price": float(original_addon_price),
                "session_token": admin_token,
                "user_email": admin_email,
            },
        )


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main_exit(run))
