#!/usr/bin/env python3
"""
TC-16: pickup slot estimate behavior differs for udka vs non-udka cart.
"""

from qa_test_utils import ensure, main_exit, post


def _make_payload(item):
    return {
        "cart_entry_id": 1,
        "position_id": item.get("position_id"),
        "name": item.get("name") or "Test",
        "description": item.get("description"),
        "photo_url": item.get("photo_url"),
        "calories": item.get("calories"),
        "price": item.get("price"),
    }


def run() -> None:
    # We only need sample items to verify route behavior, not create checkout order.
    from qa_test_utils import get

    status, positions = get("/positions")
    ensure(status == 200, f"/positions -> {status}")
    ensure(isinstance(positions, list) and positions, "/positions empty")

    udka_items = [
        p
        for p in positions
        if "udka" in str(p.get("position_type") or "").lower()
        or "udka" in str(p.get("name") or "").lower()
    ]
    non_udka_items = [
        p
        for p in positions
        if p not in udka_items
        and p.get("position_id") is not None
    ]

    if udka_items:
        status, body = post("/checkout/pickup-slot-estimate", {
            "items": [_make_payload(udka_items[0])],
        })
        ensure(
            status == 200,
            f"udka pickup-slot-estimate should work: {status}, {body}",
        )
        ensure(
            isinstance(body, dict)
            and "eta_minutes" in body
            and "eta_label" in body
            and "scheduled_pickup_at" in body,
            f"pickup-slot-estimate payload malformed: {body}",
        )

    if non_udka_items:
        status, body = post("/checkout/pickup-slot-estimate", {
            "items": [_make_payload(non_udka_items[0])],
        })
        ensure(
            status == 409,
            f"non-udka pickup-slot-estimate should be rejected: {status}, {body}",
        )


if __name__ == "__main__":
    raise SystemExit(main_exit(run))
