#!/usr/bin/env python3
"""
TC-03: /admin endpoints are protected by auth and role rules.
"""

from qa_test_utils import (
    get,
    main_exit,
    random_email,
    register,
    login,
    ensure,
)


def run() -> None:
    email = random_email("qa-regular")
    password = "SmokePass123!"
    register(email=email, password=password, name="QA Regular")
    regular = login(email=email, password=password)
    regular_token = regular["session_token"]

    # No credentials -> unauthorized.
    status, body = get("/admin/dashboard")
    ensure(status == 401, f"/admin/dashboard without auth -> {status}, {body}")

    # Regular customer token -> forbidden.
    status, body = get("/admin/dashboard", {"session_token": regular_token})
    ensure(status == 403, f"/admin/dashboard with regular token -> {status}, {body}")

    status, body = get("/admin/dashboard", {"user_email": email})
    ensure(status == 401, f"/admin/dashboard with user_email only -> {status}, {body}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
