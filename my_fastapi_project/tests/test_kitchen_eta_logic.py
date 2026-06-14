from types import SimpleNamespace
import sys
from datetime import datetime
from unittest.mock import Mock
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from fastapi import HTTPException

from checkout_service import CheckoutService
from models import (
    AdminCatalogKitchenEtaOverrideUpdateIn,
    AdminOrderStatusUpdateIn,
    CheckoutAddressPayload,
    CheckoutItemPayload,
    CheckoutVerificationIn,
)


def _make_service():
    service = CheckoutService(Mock())
    service._get_prep_time_settings_rows = lambda: []
    return service


def _position(position_type: str | None = None, name: str | None = None):
    return SimpleNamespace(position_type=position_type, name=name)


def _order_item(
    name: str | None = None,
    description: str | None = None,
    quantity: int | None = None,
):
    return SimpleNamespace(name=name, description=description, quantity=quantity)


def _checkout_order(items):
    return SimpleNamespace(items=items)


def test_zapiekanki_bucket_mapping():
    service = _make_service()

    assert service._kitchen_eta_bucket_minutes_by_queue(0) == 6
    assert service._kitchen_eta_bucket_minutes_by_queue(1) == 7
    assert service._kitchen_eta_bucket_minutes_by_queue(3) == 7
    assert service._kitchen_eta_bucket_minutes_by_queue(4) == 10
    assert service._kitchen_eta_bucket_minutes_by_queue(6) == 10
    assert service._kitchen_eta_bucket_minutes_by_queue(7) == 15
    assert service._kitchen_eta_bucket_minutes_by_queue(9) == 15
    assert service._kitchen_eta_bucket_minutes_by_queue(13) == 15
    assert service._kitchen_eta_bucket_minutes_by_queue(14) == 20


def test_kitchen_eta_overlay_cap_is_applied():
    service = _make_service()
    service._get_kitchen_eta_override_minutes = lambda: 20
    assert service._cap_kitchen_eta_total_minutes(15) == 35
    assert service._cap_kitchen_eta_total_minutes(50) == 60


def test_zapiekanki_order_detection_from_positions():
    service = _make_service()
    assert service._contains_zapiekanki_positions([
        _position(position_type="srod", name="Duza zapiekanka"),
    ])
    assert not service._contains_zapiekanki_positions([
        _position(position_type="udka", name="Udko z kurczaka"),
    ])


def test_large_zapiekanka_signature_excludes_kids_and_vac():
    service = _make_service()
    assert service._is_large_zapiekanka_signature("zapiekanki", "Pieczarka 50cm")
    assert not service._is_large_zapiekanka_signature("kids", "Kids Pieczarka 25cm")
    assert not service._is_large_zapiekanka_signature("zapiekanki_frozen", "Pieczarka VAC")


def test_zapiekanki_order_detection_in_existing_order_items():
    service = _make_service()
    assert service._is_zapiekanki_queue_order(
        _checkout_order(items=[
            _order_item(name="Zapiekanka", description="zapiek 50cm"),
        ])
    )
    assert not service._is_zapiekanki_queue_order(
        _checkout_order(items=[
            _order_item(name="Udko z kurczaka", description="udka z kurczaka"),
        ])
    )


def test_count_zapiekanki_queue_pieces_for_order_sums_quantities():
    service = _make_service()
    order = _checkout_order(
        items=[
            SimpleNamespace(
                name="Pieczarka 50cm",
                description="zapiekanka klasyczna",
                quantity=2,
            ),
            SimpleNamespace(
                name="Kids Pieczarka 25cm",
                description="kids",
                quantity=3,
            ),
            SimpleNamespace(
                name="Szynka 50cm",
                description="zapiekanka klasyczna",
                quantity=4,
            ),
        ]
    )
    assert service._count_zapiekanki_queue_pieces_for_order(order) == 6


def test_count_zapiekanki_queue_pieces_for_positions_counts_only_large_hot_items():
    service = _make_service()
    positions = [
        _position(position_type="zapiekanki", name="Pieczarka 50cm"),
        _position(position_type="zapiekanki", name="Szynka 50cm"),
        _position(position_type="kids", name="Kids Szynka 25cm"),
        _position(position_type="zapiekanki_frozen", name="Pieczarka VAC"),
    ]
    assert service._count_zapiekanki_queue_pieces_for_positions(positions) == 2


def test_count_zapiekanki_queue_pieces_for_items_prefers_position_lookup():
    service = _make_service()
    items = [
        SimpleNamespace(
            position_id=101,
            name="Pieczarka 50cm",
            description="bagietka, maslo, pieczarki",
            quantity=2,
        ),
        SimpleNamespace(
            position_id=102,
            name="Kids Pieczarka 25cm",
            description="bagietka, maslo",
            quantity=3,
        ),
    ]
    positions_by_id = {
        101: _position(position_type="zapiekanki", name="Pieczarka 50cm"),
        102: _position(position_type="kids", name="Kids Pieczarka 25cm"),
    }
    assert (
        service._count_zapiekanki_queue_pieces_for_items(
            items,
            positions_by_id=positions_by_id,
        )
        == 2
    )


def test_calculate_eta_uses_kitchen_queue_for_zapiekanki():
    service = _make_service()
    service._get_current_oven_load = lambda: 2
    service._count_waiting_zapiekanki_queue_pieces = lambda: 3
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes + 10

    eta = service._calculate_checkout_eta_minutes(
        items=[],
        fallback_minutes=999,
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        now=datetime.utcnow(),
        positions=[
            _position(position_type="zapieczaki", name="Duza zapiekanka 50cm"),
            _position(position_type="zapiekanki", name="Szynka 50cm"),
        ],
    )
    assert eta == 25


def test_calculate_eta_returns_6_for_first_single_large_zapiekanka():
    service = _make_service()
    service._get_current_oven_load = lambda: 0
    service._count_waiting_zapiekanki_queue_pieces = lambda: 0
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes

    eta = service._calculate_checkout_eta_minutes(
        items=[],
        fallback_minutes=999,
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        now=datetime.utcnow(),
        positions=[
            _position(position_type="zapiekanki", name="Pieczarka 50cm"),
        ],
    )
    assert eta == 6


def test_calculate_eta_does_not_use_zapiekanki_buckets_for_kids_only_order():
    service = _make_service()
    service._get_current_oven_load = lambda: 999
    service._count_waiting_zapiekanki_queue_pieces = lambda: 999
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes

    eta = service._calculate_checkout_eta_minutes(
        items=[],
        fallback_minutes=12,
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        now=datetime.utcnow(),
        positions=[
            _position(position_type="kids", name="Kids Pieczarka 25cm"),
        ],
    )
    assert eta == 12


def test_build_zapiekanki_batch_metrics_for_single_first_order():
    service = _make_service()
    metrics = service._build_zapiekanki_batch_metrics(
        current_oven_load=0,
        waiting_queue_pieces_before_order=0,
        slots_used_by_order=1,
    )
    assert metrics["kitchen_eta_minutes"] == 6
    assert metrics["kitchen_batch_index"] == 1
    assert metrics["kitchen_batch_count"] == 1
    assert metrics["kitchen_slots_before_order"] == 0
    assert metrics["kitchen_slots_used_by_order"] == 1


def test_build_zapiekanki_batch_metrics_keeps_order_in_first_batch_when_it_fits():
    service = _make_service()
    metrics = service._build_zapiekanki_batch_metrics(
        current_oven_load=0,
        waiting_queue_pieces_before_order=4,
        slots_used_by_order=2,
    )
    assert metrics["kitchen_eta_minutes"] == 10
    assert metrics["kitchen_batch_index"] == 1
    assert metrics["kitchen_batch_count"] == 1
    assert metrics["kitchen_slots_before_order"] == 4


def test_build_zapiekanki_batch_metrics_marks_order_as_spanning_next_batch():
    service = _make_service()
    metrics = service._build_zapiekanki_batch_metrics(
        current_oven_load=0,
        waiting_queue_pieces_before_order=4,
        slots_used_by_order=3,
    )
    assert metrics["kitchen_eta_minutes"] == 15
    assert metrics["kitchen_batch_index"] == 1
    assert metrics["kitchen_batch_count"] == 2
    assert metrics["kitchen_slots_before_order"] == 4


def test_build_zapiekanki_batch_metrics_places_order_in_second_batch():
    service = _make_service()
    metrics = service._build_zapiekanki_batch_metrics(
        current_oven_load=2,
        waiting_queue_pieces_before_order=6,
        slots_used_by_order=1,
    )
    assert metrics["kitchen_eta_minutes"] == 15
    assert metrics["kitchen_batch_index"] == 2
    assert metrics["kitchen_batch_count"] == 1
    assert metrics["kitchen_current_oven_load"] == 2
    assert metrics["kitchen_queue_pieces_before_order"] == 6


def test_oven_queue_delay_minutes_uses_batch_position_for_partially_spilling_order():
    service = _make_service()
    service._order_supports_progress_updates = lambda _: True
    service._order_oven_kind = lambda _: "zapiekanki"
    service._is_in_oven_stage = lambda _: False
    service._is_ready_for_delivery_stage = lambda _: False
    service._zapiekanki_batch_metrics_for_checkout_order = lambda *_args, **_kwargs: {
        "kitchen_batch_index": 1,
        "kitchen_batch_count": 2,
    }

    checkout_order = SimpleNamespace(
        processing_status="assigned",
        verification_stage="assigned",
    )
    assert service._oven_queue_delay_minutes(checkout_order, current_oven_load=0) == 8


def test_oven_queue_delay_minutes_returns_zero_for_first_full_batch_order():
    service = _make_service()
    service._order_supports_progress_updates = lambda _: True
    service._order_oven_kind = lambda _: "zapiekanki"
    service._is_in_oven_stage = lambda _: False
    service._is_ready_for_delivery_stage = lambda _: False
    service._zapiekanki_batch_metrics_for_checkout_order = lambda *_args, **_kwargs: {
        "kitchen_batch_index": 1,
        "kitchen_batch_count": 1,
    }

    checkout_order = SimpleNamespace(
        processing_status="assigned",
        verification_stage="assigned",
    )
    assert service._oven_queue_delay_minutes(checkout_order, current_oven_load=0) == 0


def test_update_kitchen_eta_override_updates_runtime_setting():
    service = _make_service()
    captured = {}

    service._require_admin_role = lambda **_: SimpleNamespace(user_id=42)
    service._set_decimal_runtime_setting = (
        lambda setting_key, label, decimal_value, updated_by_user_id: captured.update(
            {
                "setting_key": setting_key,
                "label": label,
                "decimal_value": decimal_value,
                "updated_by_user_id": updated_by_user_id,
            },
        )
    )
    service.get_admin_catalog = lambda session_token=None, user_email=None: {
        "kitchen_eta_override_minutes": 20,
    }

    result = service.update_kitchen_eta_override(
        AdminCatalogKitchenEtaOverrideUpdateIn(
            minutes=20,
            session_token="token",
            user_email="admin@zapieapp.pl",
        ),
    )
    assert result["kitchen_eta_override_minutes"] == 20
    assert captured["setting_key"] == "kitchen_eta_override_minutes"
    assert captured["decimal_value"] == 20
    assert captured["updated_by_user_id"] == 42


def test_update_kitchen_eta_override_rejects_invalid_minutes():
    service = _make_service()
    service._require_admin_role = lambda **_: SimpleNamespace(user_id=42)
    try:
        service.update_kitchen_eta_override(
            AdminCatalogKitchenEtaOverrideUpdateIn(
                minutes=15,
                session_token="token",
                user_email="admin@zapieapp.pl",
            )
        )
        raise AssertionError("Expected HTTPException")
    except HTTPException as exc:
        assert exc.status_code == 400


def test_preview_checkout_eta_returns_batch_metrics_for_zapiekanki():
    service = _make_service()
    service._ensure_checkout_items_are_available = lambda items: None
    service._resolve_checkout_positions = lambda items: [
        _position(position_type="zapiekanki", name="Pieczarka 50cm"),
        _position(position_type="zapiekanki", name="Szynka 50cm"),
    ]
    service._contains_udka_positions = lambda positions: False
    service._is_planned_pickup_fulfillment = lambda *_args, **_kwargs: False
    service._resolve_checkout_available_from = lambda **_: None
    service._calculate_checkout_eta_minutes = lambda **_: 15
    service._get_current_oven_load = lambda: 2
    service._count_waiting_zapiekanki_queue_pieces = lambda: 6

    payload = CheckoutVerificationIn(
        created_at=datetime.utcnow(),
        currency="PLN",
        subtotal_amount=80,
        total_amount=80,
        redeemed_points=0,
        redeemed_amount=0,
        eta_minutes=10,
        payment_method="blik",
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        address_option_index=0,
        address=CheckoutAddressPayload(
            title="Sklotowa 6/9",
            subtitle="02-220, Warszawa",
            eta_label="ok. 10 min.",
        ),
        items=[
            CheckoutItemPayload(
                cart_entry_id=1,
                position_id=101,
                name="Pieczarka 50cm",
                description="bagietka, maslo, pieczarki",
                photo_url=None,
                calories=None,
                price=40.0,
            ),
            CheckoutItemPayload(
                cart_entry_id=2,
                position_id=102,
                name="Szynka 50cm",
                description="bagietka, maslo, szynka",
                photo_url=None,
                calories=None,
                price=40.0,
            ),
        ],
        session_token="token",
        user_email="user@zapieapp.pl",
        notes=None,
    )

    preview = service.preview_checkout_eta(payload)

    assert preview.eta_minutes == 15
    assert preview.kitchen_eta_minutes == 15
    assert preview.kitchen_batch_index == 2
    assert preview.kitchen_batch_count == 1
    assert preview.kitchen_current_oven_load == 2
    assert preview.kitchen_queue_pieces_before_order == 6
    assert preview.kitchen_slots_before_order == 8
    assert preview.kitchen_slots_used_by_order == 2


def test_preview_checkout_eta_returns_empty_kitchen_metrics_for_non_zapiekanki():
    service = _make_service()
    service._ensure_checkout_items_are_available = lambda items: None
    service._resolve_checkout_positions = lambda items: [
        _position(position_type="kids", name="Kids Pieczarka 25cm"),
    ]
    service._contains_udka_positions = lambda positions: False
    service._is_planned_pickup_fulfillment = lambda *_args, **_kwargs: False
    service._resolve_checkout_available_from = lambda **_: None
    service._calculate_checkout_eta_minutes = lambda **_: 12

    payload = CheckoutVerificationIn(
        created_at=datetime.utcnow(),
        currency="PLN",
        subtotal_amount=12,
        total_amount=12,
        redeemed_points=0,
        redeemed_amount=0,
        eta_minutes=12,
        payment_method="blik",
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        address_option_index=0,
        address=CheckoutAddressPayload(
            title="Sklotowa 6/9",
            subtitle="02-220, Warszawa",
            eta_label="ok. 12 min.",
        ),
        items=[
            CheckoutItemPayload(
                cart_entry_id=1,
                position_id=201,
                name="Kids Pieczarka 25cm",
                description="kids",
                photo_url=None,
                calories=None,
                price=12.0,
            ),
        ],
        session_token="token",
        user_email="user@zapieapp.pl",
        notes=None,
    )

    preview = service.preview_checkout_eta(payload)

    assert preview.eta_minutes == 12
    assert preview.kitchen_eta_minutes is None
    assert preview.kitchen_batch_index is None
    assert preview.kitchen_batch_count == 0
    assert preview.kitchen_slots_used_by_order == 0


def test_build_admin_order_exposes_kitchen_metrics_and_disables_in_oven_for_second_batch():
    service = _make_service()
    service._remaining_eta_minutes = lambda **_: 15
    service._resolve_closed_at = lambda *_args, **_kwargs: None
    service._order_supports_progress_updates = lambda _: True
    service._order_oven_kind = lambda _: "zapiekanki"
    service._order_oven_slot_count = lambda _: 3
    service._get_effective_oven_load = lambda **_: 6
    service._oven_capacity_for_kind = lambda _kind: 6
    service._zapiekanki_batch_metrics_for_checkout_order = lambda *_args, **_kwargs: {
        "kitchen_eta_minutes": 15,
        "kitchen_batch_index": 2,
        "kitchen_batch_count": 1,
        "kitchen_capacity": 6,
        "kitchen_current_oven_load": 6,
        "kitchen_queue_pieces_before_order": 4,
        "kitchen_slots_before_order": 1,
        "kitchen_slots_used_by_order": 3,
    }

    checkout_order = SimpleNamespace(
        checkout_order_id=700,
        verification_id="phase2-admin-1",
        processing_status="assigned",
        status="active",
        verification_stage="accepted",
        created_at=datetime.utcnow(),
        active_until=None,
        payment_method="BLIK",
        fulfillment_method="odbior",
        total_amount=120.0,
        address_title="Sklotowa 6/9",
        address_subtitle="Punkt odbioru",
        notes=None,
        assigned_to_user_id=7,
        items=[
            SimpleNamespace(name="Pieczarka 50cm", quantity=1, price=40.0, description=None),
            SimpleNamespace(name="Szynka 50cm", quantity=1, price=40.0, description=None),
            SimpleNamespace(name="Salame 50cm", quantity=1, price=40.0, description=None),
        ],
        chat_messages=[
            SimpleNamespace(sender_role="customer", staff_read_at=None),
            SimpleNamespace(sender_role="employee", staff_read_at=None),
        ],
    )

    order = service._build_admin_order(
        checkout_order,
        customer_email="customer@zapieapp.pl",
        now=datetime.utcnow(),
        current_user_id=7,
        assigned_operator_email="employee@zapieapp.pl",
        current_oven_load=6,
    )

    assert order.can_mark_in_oven is False
    assert order.kitchen_eta_minutes == 15
    assert order.kitchen_batch_index == 2
    assert order.kitchen_batch_count == 1
    assert order.kitchen_capacity == 6
    assert order.kitchen_current_oven_load == 6
    assert order.kitchen_queue_pieces_before_order == 4
    assert order.kitchen_slots_before_order == 1
    assert order.kitchen_slots_used_by_order == 3
    assert order.unread_customer_message_count == 1
    assert order.assigned_to_me is True
    assert order.assigned_operator_email == "employee@zapieapp.pl"


def test_update_admin_order_status_rejects_in_oven_when_order_does_not_fit_current_batch():
    service = _make_service()
    checkout_order = SimpleNamespace(
        checkout_order_id=701,
        verification_id="phase2-admin-2",
        processing_status="assigned",
        verification_stage="accepted",
        items=[
            SimpleNamespace(name="Pieczarka 50cm", quantity=2, description="zapiekanka"),
        ],
        chat_messages=[],
    )

    db_query = Mock()
    db_query.options.return_value = db_query
    db_query.filter.return_value = db_query
    db_query.first.return_value = checkout_order
    service.db.query = Mock(return_value=db_query)

    service._require_admin_user = lambda **_: SimpleNamespace(role="employee", user_id=7)
    service._normalize_processing_status = lambda _status: "assigned"
    service._normalize_operator_verification_stage = lambda **_: "in_oven"
    service._is_driver_order = lambda _: False
    service._order_supports_progress_updates = lambda _: True
    service._get_opening_time = lambda: "12:00"
    service._get_closing_time = lambda: "21:00"
    service._is_open_now = lambda **_: True
    service._order_oven_kind = lambda _: "zapiekanki"
    service._get_current_oven_load = lambda **_: 0
    service._order_oven_slot_count = lambda _: 2
    service._oven_capacity_for_kind = lambda _kind: 6
    service._zapiekanki_batch_metrics_for_checkout_order = lambda *_args, **_kwargs: {
        "kitchen_batch_index": 2,
        "kitchen_batch_count": 1,
        "kitchen_slots_before_order": 6,
    }

    try:
        service.update_admin_order_status(
            701,
            AdminOrderStatusUpdateIn(
                processing_status="assigned",
                verification_stage="in_oven",
                session_token="token",
                user_email="employee@zapieapp.pl",
            ),
        )
        raise AssertionError("Expected HTTPException")
    except HTTPException as exc:
        assert exc.status_code == 409
        assert "aktualnym wsadzie pieca" in exc.detail


if __name__ == "__main__":
    test_zapiekanki_bucket_mapping()
    test_kitchen_eta_overlay_cap_is_applied()
    test_zapiekanki_order_detection_from_positions()
    test_large_zapiekanka_signature_excludes_kids_and_vac()
    test_zapiekanki_order_detection_in_existing_order_items()
    test_count_zapiekanki_queue_pieces_for_order_sums_quantities()
    test_count_zapiekanki_queue_pieces_for_positions_counts_only_large_hot_items()
    test_count_zapiekanki_queue_pieces_for_items_prefers_position_lookup()
    test_calculate_eta_uses_kitchen_queue_for_zapiekanki()
    test_calculate_eta_returns_6_for_first_single_large_zapiekanka()
    test_calculate_eta_does_not_use_zapiekanki_buckets_for_kids_only_order()
    test_build_zapiekanki_batch_metrics_for_single_first_order()
    test_build_zapiekanki_batch_metrics_keeps_order_in_first_batch_when_it_fits()
    test_build_zapiekanki_batch_metrics_marks_order_as_spanning_next_batch()
    test_build_zapiekanki_batch_metrics_places_order_in_second_batch()
    test_oven_queue_delay_minutes_uses_batch_position_for_partially_spilling_order()
    test_oven_queue_delay_minutes_returns_zero_for_first_full_batch_order()
    test_update_kitchen_eta_override_updates_runtime_setting()
    test_update_kitchen_eta_override_rejects_invalid_minutes()
    test_preview_checkout_eta_returns_batch_metrics_for_zapiekanki()
    test_preview_checkout_eta_returns_empty_kitchen_metrics_for_non_zapiekanki()
    test_build_admin_order_exposes_kitchen_metrics_and_disables_in_oven_for_second_batch()
    test_update_admin_order_status_rejects_in_oven_when_order_does_not_fit_current_batch()
    print("OK: test_kitchen_eta_logic.py")
