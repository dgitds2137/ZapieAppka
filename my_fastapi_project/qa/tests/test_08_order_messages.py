#!/usr/bin/env python3
"""
TC-08: customer message thread lifecycle (create and read on a checkout order).
"""

from qa_test_utils import (
    create_checkout_verification,
    ensure,
    get,
    main_exit,
    make_checkout_items,
    post,
    random_email,
    register,
    login,
)


def run() -> None:
    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list) and positions, "/positions empty")

    email = random_email("qa-message")
    password = "SmokePass123!"
    register(email=email, password=password, name="QA Message")
    customer = login(email=email, password=password)
    token = customer["session_token"]

    items = make_checkout_items(positions, target_total=60.0)
    verification = create_checkout_verification(session_token=token, items=items)
    checkout_order_id = int(verification.get("saved_order_id"))
    verification_id = verification.get("verification_id")
    ensure(checkout_order_id > 0, f"invalid checkout_order_id: {verification}")

    status, body = get(f"/checkout/orders/{checkout_order_id}/messages")
    ensure(status == 401, f"messages without auth unexpected: {status}, {body}")

    status, messages = get(
        f"/checkout/orders/{checkout_order_id}/messages",
        {"session_token": token, "email": email},
    )
    ensure(status == 200, f"messages with auth failed: {status}, {messages}")
    ensure(isinstance(messages, list), "messages malformed")
    messages_count = len(messages)

    message_text = f"QA test message for {verification_id}"
    status, created = post(
        f"/checkout/orders/{checkout_order_id}/messages",
        {
            "message": message_text,
            "session_token": token,
            "user_email": email,
        },
    )
    ensure(status == 200, f"create message failed: {status}, {created}")
    ensure(isinstance(created, dict), f"create message malformed: {created}")
    ensure(created.get("message") == message_text, f"message text mismatch: {created}")

    status, messages = get(
        f"/checkout/orders/{checkout_order_id}/messages",
        {"session_token": token, "email": email},
    )
    ensure(status == 200, f"messages after write failed: {status}, {messages}")
    ensure(len(messages) == messages_count + 1, "message count did not grow")
    ensure(
        any((m.get("message") == message_text) for m in messages if isinstance(m, dict)),
        f"written message missing in thread: {messages}",
    )

    status, read = post(
        f"/checkout/orders/{checkout_order_id}/messages/read",
        {"session_token": token, "user_email": email},
    )
    ensure(
        status in (401, 403),
        f"customer read endpoint should be forbidden/unauthorized: {status}, {read}",
    )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
