from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock
import sys

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from checkout_service import CheckoutService


def _make_service():
    return CheckoutService(Mock())


def test_stage2_smoke() -> None:
    service = _make_service()

    assert service._kitchen_eta_bucket_minutes_by_queue(0) == 6
    assert service._kitchen_eta_bucket_minutes_by_queue(1) == 7
    assert service._kitchen_eta_bucket_minutes_by_queue(3) == 7
    assert service._kitchen_eta_bucket_minutes_by_queue(4) == 10
    assert service._kitchen_eta_bucket_minutes_by_queue(8) == 10
    assert service._kitchen_eta_bucket_minutes_by_queue(9) == 15
    assert service._kitchen_eta_bucket_minutes_by_queue(13) == 15
    assert service._kitchen_eta_bucket_minutes_by_queue(14) == 20

    service._get_kitchen_eta_override_minutes = lambda: 20
    assert service._cap_kitchen_eta_total_minutes(15) == 35
    assert service._cap_kitchen_eta_total_minutes(50) == 60

    service._kitchen_eta_bucket_minutes_by_queue = lambda: 15
    service._cap_kitchen_eta_total_minutes = lambda automatic_minutes: automatic_minutes + 10

    eta = service._calculate_checkout_eta_minutes(
        items=[],
        fallback_minutes=999,
        fulfillment_method="odbior",
        fulfillment_option_index=1,
        now=datetime.utcnow(),
        positions=[
            SimpleNamespace(position_type="zapiekanki", name="Duza zapiekanka 50cm"),
        ],
    )
    assert eta == 25


def test_stage2_kitchen_item_detection() -> None:
    service = _make_service()

    assert service._contains_zapiekanki_positions([
        SimpleNamespace(position_type="zapiekanki", name="Zapiekanka z serem"),
    ])
    assert not service._contains_zapiekanki_positions([
        SimpleNamespace(position_type="udka", name="Udko z kurczaka"),
    ])
    assert service._is_zapiekanki_order_item("Duza zapiekanka", "serowa")
    assert not service._is_zapiekanki_order_item("Frytki", "duze")


if __name__ == "__main__":
    test_stage2_smoke()
    test_stage2_kitchen_item_detection()
    print("OK: etap 2 smoke (unit)")
