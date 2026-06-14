from __future__ import annotations

import argparse
import json
from copy import deepcopy
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ARTIFACT_ROOT = Path(__file__).resolve().parent / "artifacts" / "time_zapiekanki_phase2_api_smoke"


@dataclass
class ScenarioResult:
    name: str
    expected_eta_minutes: int | None
    actual_eta_minutes: int | None
    expected_kitchen_eta_minutes: int | None
    actual_kitchen_eta_minutes: int | None
    expected_kitchen_batch_index: int | None
    actual_kitchen_batch_index: int | None
    expected_kitchen_slots_used_by_order: int | None
    actual_kitchen_slots_used_by_order: int | None
    passed: bool | None
    note: str
    response: dict[str, Any] | None


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    return _read_json_response(request)


def _patch_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="PATCH",
    )
    return _read_json_response(request)


def _get_json(url: str, query: dict[str, str] | None = None) -> dict[str, Any]:
    full_url = url
    if query:
        full_url = f"{url}?{urlencode(query)}"
    request = Request(
        full_url,
        headers={"Accept": "application/json"},
        method="GET",
    )
    return _read_json_response(request)


def _read_json_response(request: Request) -> dict[str, Any]:
    try:
        with urlopen(request, timeout=20) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw.strip() else {}
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for {request.full_url}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"Network error for {request.full_url}: {exc}") from exc


def _large_item(cart_entry_id: int, position_id: int, name: str) -> dict[str, Any]:
    return {
        "cart_entry_id": cart_entry_id,
        "position_id": position_id,
        "name": name,
        "description": "bagietka, maslo, skladniki klasyczne",
        "photo_url": None,
        "calories": None,
        "price": 40.0,
    }


def _non_kitchen_item(cart_entry_id: int, position_id: int, name: str, description: str, price: float) -> dict[str, Any]:
    return {
        "cart_entry_id": cart_entry_id,
        "position_id": position_id,
        "name": name,
        "description": description,
        "photo_url": None,
        "calories": None,
        "price": price,
    }


def _base_payload(items: list[dict[str, Any]], *, eta_minutes: int, total_amount: float) -> dict[str, Any]:
    return {
        "created_at": _utc_now_iso(),
        "currency": "PLN",
        "subtotal_amount": total_amount,
        "total_amount": total_amount,
        "redeemed_points": 0,
        "redeemed_amount": 0.0,
        "eta_minutes": eta_minutes,
        "payment_method": "preview",
        "fulfillment_method": "odbior",
        "fulfillment_option_index": 1,
        "address_option_index": 0,
        "address": {
            "title": "Sklotowa 6/9",
            "subtitle": "Punkt odbioru",
            "eta_label": "preview",
        },
        "items": items,
        "session_token": "phase2-smoke",
        "user_email": "phase2-smoke@zapieapp.pl",
        "notes": "time_zapiekanki_phase2_api_smoke",
    }


def _load_catalog_positions(api_base_url: str) -> list[dict[str, Any]]:
    positions = _get_json(f"{api_base_url}/positions")
    if not isinstance(positions, list):
        raise RuntimeError("/positions did not return a list")
    return [dict(item) for item in positions if isinstance(item, dict)]


def _is_large_hot_zapiekanka(position: dict[str, Any]) -> bool:
    if not position.get("is_active", False):
        return False
    position_type = str(position.get("position_type") or "").strip().lower()
    if position_type != "zapiekanki":
        return False
    name = str(position.get("name") or "").strip()
    return "25cm" not in name and "vac" not in name.lower()


def _resolve_phase2_catalog_inputs(api_base_url: str) -> dict[str, dict[str, Any]]:
    positions = _load_catalog_positions(api_base_url)

    large_hot = next((item for item in positions if _is_large_hot_zapiekanka(item)), None)
    if large_hot is None:
        raise RuntimeError("No active large hot zapiekanka found in /positions")

    vac_item = next(
        (
            item
            for item in positions
            if str(item.get("position_type") or "").strip().lower() == "zapiekanki_frozen"
            and item.get("is_active", False)
        ),
        None,
    )
    if vac_item is None:
        raise RuntimeError("No active VAC position found in /positions")

    kids_item = next(
        (
            item
            for item in positions
            if str(item.get("position_type") or "").strip().lower() == "kids"
            and item.get("is_active", False)
        ),
        None,
    )
    if kids_item is None:
        raise RuntimeError("No active kids position found in /positions")

    return {
        "large_hot": large_hot,
        "vac": vac_item,
        "kids": kids_item,
    }


def _large_items_from_catalog(count: int, position: dict[str, Any]) -> list[dict[str, Any]]:
    position_id = int(position["position_id"])
    name = str(position.get("name") or "Zapiekanka 50cm")
    return [_large_item(index, position_id, name) for index in range(1, count + 1)]


def _non_kitchen_items_from_catalog(vac_position: dict[str, Any], kids_position: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        _non_kitchen_item(
            1,
            int(vac_position["position_id"]),
            str(vac_position.get("name") or "VAC"),
            str(vac_position.get("description") or "zapiekanki_frozen vac"),
            float(vac_position.get("price") or 0.0),
        ),
        _non_kitchen_item(
            2,
            int(kids_position["position_id"]),
            str(kids_position.get("name") or "Kids 25cm"),
            str(kids_position.get("description") or "kids"),
            float(kids_position.get("price") or 0.0),
        ),
    ]


def _build_scenarios(catalog_inputs: dict[str, dict[str, Any]]) -> list[tuple[str, dict[str, Any], dict[str, Any]]]:
    large_hot = catalog_inputs["large_hot"]
    vac_item = catalog_inputs["vac"]
    kids_item = catalog_inputs["kids"]

    one_large = _large_items_from_catalog(1, large_hot)
    four_large = _large_items_from_catalog(4, large_hot)
    seven_large = _large_items_from_catalog(7, large_hot)
    ten_large = _large_items_from_catalog(10, large_hot)
    fourteen_large = _large_items_from_catalog(14, large_hot)
    vac_only = _non_kitchen_items_from_catalog(vac_item, kids_item)

    return [
        (
            "one_large_clean_queue",
            _base_payload(one_large, eta_minutes=10, total_amount=40.0),
            {
                "eta_minutes": 6,
                "kitchen_eta_minutes": 6,
                "kitchen_batch_index": 1,
                "kitchen_slots_used_by_order": 1,
            },
        ),
        (
            "four_large_clean_queue",
            _base_payload(four_large, eta_minutes=10, total_amount=160.0),
            {
                "eta_minutes": 10,
                "kitchen_eta_minutes": 10,
                "kitchen_batch_index": 1,
                "kitchen_slots_used_by_order": 4,
            },
        ),
        (
            "seven_large_clean_queue",
            _base_payload(seven_large, eta_minutes=10, total_amount=280.0),
            {
                "eta_minutes": 15,
                "kitchen_eta_minutes": 15,
                "kitchen_batch_index": 1,
                "kitchen_slots_used_by_order": 7,
            },
        ),
        (
            "ten_large_clean_queue",
            _base_payload(ten_large, eta_minutes=10, total_amount=400.0),
            {
                "eta_minutes": 15,
                "kitchen_eta_minutes": 15,
                "kitchen_batch_index": 1,
                "kitchen_slots_used_by_order": 10,
            },
        ),
        (
            "fourteen_large_clean_queue",
            _base_payload(fourteen_large, eta_minutes=10, total_amount=560.0),
            {
                "eta_minutes": 20,
                "kitchen_eta_minutes": 20,
                "kitchen_batch_index": 1,
                "kitchen_slots_used_by_order": 14,
            },
        ),
        (
            "vac_and_25cm_non_kitchen",
            _base_payload(
                vac_only,
                eta_minutes=12,
                total_amount=sum(float(item["price"]) for item in vac_only),
            ),
            {
                "eta_minutes": 12,
                "kitchen_eta_minutes": None,
                "kitchen_batch_index": None,
                "kitchen_slots_used_by_order": 0,
            },
        ),
    ]


def _compare_response(name: str, expected: dict[str, Any], response: dict[str, Any], strict: bool) -> ScenarioResult:
    actual_eta = response.get("eta_minutes")
    actual_kitchen_eta = response.get("kitchen_eta_minutes")
    actual_batch_index = response.get("kitchen_batch_index")
    actual_slots_used = response.get("kitchen_slots_used_by_order")

    if not strict:
        return ScenarioResult(
            name=name,
            expected_eta_minutes=expected.get("eta_minutes"),
            actual_eta_minutes=actual_eta,
            expected_kitchen_eta_minutes=expected.get("kitchen_eta_minutes"),
            actual_kitchen_eta_minutes=actual_kitchen_eta,
            expected_kitchen_batch_index=expected.get("kitchen_batch_index"),
            actual_kitchen_batch_index=actual_batch_index,
            expected_kitchen_slots_used_by_order=expected.get("kitchen_slots_used_by_order"),
            actual_kitchen_slots_used_by_order=actual_slots_used,
            passed=None,
            note="report-only mode; no strict assertion against clean queue assumptions",
            response=response,
        )

    passed = (
        actual_eta == expected.get("eta_minutes")
        and actual_kitchen_eta == expected.get("kitchen_eta_minutes")
        and actual_batch_index == expected.get("kitchen_batch_index")
        and actual_slots_used == expected.get("kitchen_slots_used_by_order")
    )
    note = "strict clean queue comparison passed" if passed else "strict clean queue comparison failed"
    return ScenarioResult(
        name=name,
        expected_eta_minutes=expected.get("eta_minutes"),
        actual_eta_minutes=actual_eta,
        expected_kitchen_eta_minutes=expected.get("kitchen_eta_minutes"),
        actual_kitchen_eta_minutes=actual_kitchen_eta,
        expected_kitchen_batch_index=expected.get("kitchen_batch_index"),
        actual_kitchen_batch_index=actual_batch_index,
        expected_kitchen_slots_used_by_order=expected.get("kitchen_slots_used_by_order"),
        actual_kitchen_slots_used_by_order=actual_slots_used,
        passed=passed,
        note=note,
        response=response,
    )


def _run_override_smoke(
    api_base_url: str,
    override_minutes: int,
    admin_session_token: str,
    admin_email: str,
    strict: bool,
) -> ScenarioResult:
    catalog_url = f"{api_base_url}/admin/catalog"
    patch_url = f"{api_base_url}/admin/catalog/kitchen-eta"
    preview_url = f"{api_base_url}/checkout/eta-preview"

    original_catalog = _get_json(
        catalog_url,
        {
            "session_token": admin_session_token,
            "email": admin_email,
        },
    )
    original_override = int(original_catalog.get("kitchen_eta_override_minutes") or 0)
    catalog_inputs = _resolve_phase2_catalog_inputs(api_base_url)
    large_hot = catalog_inputs["large_hot"]

    try:
        _patch_json(
            patch_url,
            {
                "minutes": override_minutes,
                "session_token": admin_session_token,
                "user_email": admin_email,
            },
        )

        payload = _base_payload(
            _large_items_from_catalog(1, large_hot),
            eta_minutes=10,
            total_amount=float(large_hot.get("price") or 0.0),
        )
        response = _post_json(preview_url, payload)
        expected_eta = 6 + override_minutes
        expected = {
            "eta_minutes": expected_eta,
            "kitchen_eta_minutes": expected_eta,
            "kitchen_batch_index": 1,
            "kitchen_slots_used_by_order": 1,
        }
        result = _compare_response(
            name=f"override_{override_minutes}_one_large_clean_queue",
            expected=expected,
            response=response,
            strict=strict,
        )
        result.note += f"; original_override={original_override}"
        return result
    finally:
        _patch_json(
            patch_url,
            {
                "minutes": original_override,
                "session_token": admin_session_token,
                "user_email": admin_email,
            },
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="TIME_ZAPIEKANKI Phase 2 API preview smoke runner")
    parser.add_argument("--api-base-url", default="https://zapieapp-api-dev-alpha.ambitiousstone-9e7294a6.polandcentral.azurecontainerapps.io")
    parser.add_argument("--strict-clean-queue", action="store_true")
    parser.add_argument("--output-path", default=None)
    parser.add_argument("--override-minutes", type=int, default=None)
    parser.add_argument("--admin-session-token", default=None)
    parser.add_argument("--admin-email", default=None)
    args = parser.parse_args()

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    if args.output_path:
        summary_path = Path(args.output_path).resolve()
        summary_path.parent.mkdir(parents=True, exist_ok=True)
    else:
        run_dir = ARTIFACT_ROOT / timestamp
        run_dir.mkdir(parents=True, exist_ok=True)
        summary_path = run_dir / "summary.json"

    preview_url = f"{args.api_base_url}/checkout/eta-preview"
    results: list[ScenarioResult] = []
    catalog_inputs = _resolve_phase2_catalog_inputs(args.api_base_url)

    for name, payload, expected in _build_scenarios(catalog_inputs):
        response = _post_json(preview_url, deepcopy(payload))
        results.append(
            _compare_response(
                name=name,
                expected=expected,
                response=response,
                strict=args.strict_clean_queue,
            )
        )

    if args.override_minutes is not None:
        if not args.admin_session_token or not args.admin_email:
            raise SystemExit("--override-minutes wymaga --admin-session-token i --admin-email")
        results.append(
            _run_override_smoke(
                api_base_url=args.api_base_url,
                override_minutes=args.override_minutes,
                admin_session_token=args.admin_session_token,
                admin_email=args.admin_email,
                strict=args.strict_clean_queue,
            )
        )

    payload = {
        "timestamp": timestamp,
        "api_base_url": args.api_base_url,
        "strict_clean_queue": args.strict_clean_queue,
        "results": [asdict(result) for result in results],
    }
    summary_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Saved smoke summary to {summary_path}")
    for result in results:
        state = "PASS" if result.passed else ("FAIL" if result.passed is False else "INFO")
        print(
            f"[{state}] {result.name}: "
            f"expected_eta={result.expected_eta_minutes} actual_eta={result.actual_eta_minutes} "
            f"expected_batch={result.expected_kitchen_batch_index} actual_batch={result.actual_kitchen_batch_index} "
            f"note={result.note}"
        )

    if args.strict_clean_queue and any(result.passed is False for result in results):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
