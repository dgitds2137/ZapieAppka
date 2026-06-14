from pathlib import Path
import sys
from unittest.mock import Mock

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "my_fastapi_project") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "my_fastapi_project"))

from main import MenuService, UserService
from models import CheckoutVerificationIn
from router import routes


def _preview_request_payload() -> dict:
    return {
        "created_at": "2026-06-14T12:00:00Z",
        "currency": "PLN",
        "subtotal_amount": 80.0,
        "total_amount": 80.0,
        "redeemed_points": 0,
        "redeemed_amount": 0.0,
        "eta_minutes": 10,
        "payment_method": "blik",
        "fulfillment_method": "odbior",
        "fulfillment_option_index": 1,
        "address_option_index": 0,
        "address": {
            "title": "Sklotowa 6/9",
            "subtitle": "02-220, Warszawa",
            "eta_label": "ok. 10 min.",
        },
        "items": [
            {
                "cart_entry_id": 1,
                "position_id": 101,
                "name": "Pieczarka 50cm",
                "description": "bagietka, maslo, pieczarki",
                "photo_url": None,
                "calories": None,
                "price": 40.0,
            },
            {
                "cart_entry_id": 2,
                "position_id": 102,
                "name": "Szynka 50cm",
                "description": "bagietka, maslo, szynka",
                "photo_url": None,
                "calories": None,
                "price": 40.0,
            },
        ],
        "session_token": "token",
        "user_email": "user@zapieapp.pl",
        "notes": "bez cebuli",
    }


class _FakeCheckoutServiceSuccess:
    def __init__(self, db):
        self.db = db
        self.last_payload = None

    def preview_checkout_eta(self, payload: CheckoutVerificationIn):
        self.last_payload = payload
        return {
            "eta_minutes": 15,
            "available_from": None,
            "scheduled_pickup_at": None,
            "kitchen_eta_minutes": 15,
            "kitchen_batch_index": 2,
            "kitchen_batch_count": 1,
            "kitchen_capacity": 6,
            "kitchen_current_oven_load": 2,
            "kitchen_queue_pieces_before_order": 6,
            "kitchen_slots_before_order": 8,
            "kitchen_slots_used_by_order": 2,
        }


class _FakeCheckoutServiceFailure:
    def __init__(self, db):
        self.db = db

    def preview_checkout_eta(self, payload: CheckoutVerificationIn):
        raise HTTPException(
            status_code=409,
            detail="Czesc pozycji nie jest juz dostepna.",
        )


def _build_test_client(service_cls):
    def _fake_db():
        yield Mock()

    test_app = FastAPI()
    test_app.include_router(
        routes(
            MenuService,
            UserService,
            service_cls,
            _fake_db,
        ),
    )
    return TestClient(test_app)


def test_checkout_eta_preview_endpoint_success():
    fake_service = _FakeCheckoutServiceSuccess(None)
    client = _build_test_client(lambda db: fake_service)

    response = client.post(
        "/checkout/eta-preview",
        json=_preview_request_payload(),
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["eta_minutes"] == 15
    assert data["kitchen_eta_minutes"] == 15
    assert data["kitchen_batch_index"] == 2
    assert data["kitchen_batch_count"] == 1
    assert data["kitchen_slots_used_by_order"] == 2
    assert fake_service.last_payload is not None
    assert fake_service.last_payload.fulfillment_option_index == 1
    assert len(fake_service.last_payload.items) == 2
    assert fake_service.last_payload.items[0].name == "Pieczarka 50cm"


def test_checkout_eta_preview_endpoint_propagates_backend_error():
    client = _build_test_client(_FakeCheckoutServiceFailure)

    response = client.post(
        "/checkout/eta-preview",
        json=_preview_request_payload(),
    )

    assert response.status_code == 409
    assert "nie jest juz dostepna" in response.text.lower()


if __name__ == "__main__":
    test_checkout_eta_preview_endpoint_success()
    test_checkout_eta_preview_endpoint_propagates_backend_error()
    print("OK: endpoint test for checkout eta preview")
