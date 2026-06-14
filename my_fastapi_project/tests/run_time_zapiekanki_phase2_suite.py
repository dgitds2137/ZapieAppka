from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "my_fastapi_project") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "my_fastapi_project"))

from test_kitchen_eta_logic import (
    test_build_admin_order_exposes_kitchen_metrics_and_disables_in_oven_for_second_batch,
    test_build_zapiekanki_batch_metrics_for_single_first_order,
    test_build_zapiekanki_batch_metrics_keeps_order_in_first_batch_when_it_fits,
    test_build_zapiekanki_batch_metrics_marks_order_as_spanning_next_batch,
    test_build_zapiekanki_batch_metrics_places_order_in_second_batch,
    test_calculate_eta_uses_kitchen_queue_for_zapiekanki,
    test_calculate_eta_returns_6_for_first_single_large_zapiekanka,
    test_calculate_eta_does_not_use_zapiekanki_buckets_for_kids_only_order,
    test_kitchen_eta_overlay_cap_is_applied,
    test_oven_queue_delay_minutes_uses_batch_position_for_partially_spilling_order,
    test_oven_queue_delay_minutes_returns_zero_for_first_full_batch_order,
    test_preview_checkout_eta_returns_batch_metrics_for_zapiekanki,
    test_preview_checkout_eta_returns_empty_kitchen_metrics_for_non_zapiekanki,
    test_update_admin_order_status_rejects_in_oven_when_order_does_not_fit_current_batch,
    test_zapiekanki_bucket_mapping,
)
from test_admin_kitchen_eta_endpoint import (
    test_kitchen_eta_endpoint_success,
    test_kitchen_eta_endpoint_rejects_invalid_minutes,
)
from test_checkout_eta_preview_endpoint import (
    test_checkout_eta_preview_endpoint_success,
    test_checkout_eta_preview_endpoint_propagates_backend_error,
)
from test_checkout_active_endpoint_phase2 import (
    test_checkout_active_endpoint_returns_kitchen_diagnostics,
    test_checkout_active_endpoint_returns_null_when_no_active_order,
)
from test_admin_order_processing_status_phase2_endpoint import (
    test_admin_order_processing_status_endpoint_maps_kitchen_diagnostics,
    test_admin_order_processing_status_endpoint_propagates_in_oven_conflict,
)


def main() -> None:
    tests = [
        test_zapiekanki_bucket_mapping,
        test_kitchen_eta_overlay_cap_is_applied,
        test_calculate_eta_uses_kitchen_queue_for_zapiekanki,
        test_calculate_eta_returns_6_for_first_single_large_zapiekanka,
        test_calculate_eta_does_not_use_zapiekanki_buckets_for_kids_only_order,
        test_build_zapiekanki_batch_metrics_for_single_first_order,
        test_build_zapiekanki_batch_metrics_keeps_order_in_first_batch_when_it_fits,
        test_build_zapiekanki_batch_metrics_marks_order_as_spanning_next_batch,
        test_build_zapiekanki_batch_metrics_places_order_in_second_batch,
        test_build_admin_order_exposes_kitchen_metrics_and_disables_in_oven_for_second_batch,
        test_oven_queue_delay_minutes_uses_batch_position_for_partially_spilling_order,
        test_oven_queue_delay_minutes_returns_zero_for_first_full_batch_order,
        test_preview_checkout_eta_returns_batch_metrics_for_zapiekanki,
        test_preview_checkout_eta_returns_empty_kitchen_metrics_for_non_zapiekanki,
        test_update_admin_order_status_rejects_in_oven_when_order_does_not_fit_current_batch,
        test_kitchen_eta_endpoint_success,
        test_kitchen_eta_endpoint_rejects_invalid_minutes,
        test_checkout_eta_preview_endpoint_success,
        test_checkout_eta_preview_endpoint_propagates_backend_error,
        test_checkout_active_endpoint_returns_kitchen_diagnostics,
        test_checkout_active_endpoint_returns_null_when_no_active_order,
        test_admin_order_processing_status_endpoint_maps_kitchen_diagnostics,
        test_admin_order_processing_status_endpoint_propagates_in_oven_conflict,
    ]

    for test_fn in tests:
        test_fn()

    print("OK: Phase 2 TIME_ZAPIEKANKI suite passed")


if __name__ == "__main__":
    main()
