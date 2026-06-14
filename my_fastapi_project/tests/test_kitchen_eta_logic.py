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
from models import AdminCatalogKitchenEtaOverrideUpdateIn


def _make_service():
    service = CheckoutService(Mock())
    service._get_prep_time_settings_rows = lambda: []
    return service


def _position(position_type: str | None = None, name: str | None = None):
    return SimpleNamespace(position_type=position_type, name=name)


def _order_item(name: str | None = None, description: str | None = None):
    return SimpleNamespace(name=name, description=description)


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
    service._count_active_zapiekanki_queue = lambda: 5
    service._kitchen_eta_bucket_minutes_by_queue = lambda queue_size: 15 if queue_size == 7 else 999
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
    service._count_active_zapiekanki_queue = lambda: 0
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes
    service._kitchen_eta_bucket_minutes_by_queue = lambda queue_size: 999

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
    service._count_active_zapiekanki_queue = lambda: 999
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes
    service._kitchen_eta_bucket_minutes_by_queue = lambda queue_size: 999

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
    test_update_kitchen_eta_override_updates_runtime_setting()
    test_update_kitchen_eta_override_rejects_invalid_minutes()
    print("OK: test_kitchen_eta_logic.py")
