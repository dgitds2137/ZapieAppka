#!/usr/bin/env python3
"""
TC-02: customer register + login basics, duplicates and wrong credentials handling.
"""

from qa_test_utils import (
    main_exit,
    ensure,
    post_form,
    login,
    register,
    random_email,
    b64,
)


def run() -> None:
    email = random_email("qa-customer")
    password = "SmokePass123!"

    reg = register(email=email, password=password, name="QA Customer")
    ensure(reg.get("email") == email, f"register response email mismatch: {reg}")
    ensure(reg.get("session_token"), "register missing session_token")

    logged = login(email=email, password=password)
    ensure(logged.get("session_token"), "login missing session_token")
    ensure(logged.get("email") == email, f"login response email mismatch: {logged}")

    # Duplicate should be rejected.
    status, body = post_form(
        "/register",
        {
            "email": email,
            "password": b64(password),
            "name": "QA Customer duplicate",
            "phone": "123456789",
        },
    )
    ensure(status == 409, f"duplicate register unexpected status: {status}, body={body}")

    # Bad password should be unauthorized.
    status, body = post_form(
        "/login",
        {"email": email, "password": b64("WrongPass123!")},
    )
    ensure(status == 401, f"wrong login status unexpected: {status}, body={body}")


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
