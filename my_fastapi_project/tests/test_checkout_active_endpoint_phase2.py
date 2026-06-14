from pathlib import Path
import sys
from unittest.mock import Mock

from fastapi import FastAPI
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "my_fastapi_project") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "my_fastapi_project"))

from main import MenuService, UserService
from router import routes


class _FakeCheckoutServiceActiveSuccess:
    def __init__(self, db):
        self.db = db
        self.last_session_token = None
        self.last_user_email = None

    def get_active_checkout(self, session_token=None, user_email=None):
        self.last_session_token = session_token
        self.last_user_email = user_email
        return {
            "verification_id": "ord-phase2-active",
            "saved_order_id": 913,
            "status": "active",
            "processing_status": "assigned",
            "payment_method": "BLIK",
            "verification_stage": "accepted",
            "message": "ok",
            "created_at": "2026-06-14T12:00:00Z",
            "remaining_eta_minutes": 11,
            "kitchen_eta_minutes": 15,
            "kitchen_batch_index": 2,
            "kitchen_batch_count": 2,
            "kitchen_capacity": 6,
            "kitchen_current_oven_load": 4,
            "kitchen_queue_pieces_before_order": 6,
            "kitchen_slots_before_order": 1,
            "kitchen_slots_used_by_order": 2,
            "received_order": {
                "created_at": "2026-06-14T12:00:00Z",
                "currency": "PLN",
                "subtotal_amount": 80.0,
                "total_amount": 80.0,
                "redeemed_points": 0,
                "redeemed_amount": 0.0,
                "eta_minutes": 10,
                "payment_method": "BLIK",
                "fulfillment_method": "odbior",
                "fulfillment_option_index": 0,
                "address_option_index": 0,
                "address": {
                    "title": "Sklotowa 6/9",
                    "subtitle": "Punkt odbioru",
                    "eta_label": "ok. 15 min",
                },
                "items": [
                    {
                        "cart_entry_id": 1,
                        "position_id": 101,
                        "name": "Pieczarka 50cm",
                        "price": 40.0,
                    },
                    {
                        "cart_entry_id": 2,
                        "position_id": 101,
                        "name": "Pieczarka 50cm",
                        "price": 40.0,
                    },
                ],
                "session_token": "session-customer",
                "user_email": "customer@zapieapp.pl",
            },
        }


class _FakeCheckoutServiceActiveEmpty:
    def __init__(self, db):
        self.db = db

    def get_active_checkout(self, session_token=None, user_email=None):
        return None


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


def test_checkout_active_endpoint_returns_kitchen_diagnostics():
    fake_service = _FakeCheckoutServiceActiveSuccess(None)
    client = _build_test_client(lambda db: fake_service)

    response = client.get(
        "/checkout/active",
        params={
            "session_token": "session-customer",
            "email": "customer@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["verification_id"] == "ord-phase2-active"
    assert data["remaining_eta_minutes"] == 11
    assert data["kitchen_eta_minutes"] == 15
    assert data["kitchen_batch_index"] == 2
    assert data["kitchen_batch_count"] == 2
    assert data["kitchen_current_oven_load"] == 4
    assert data["kitchen_queue_pieces_before_order"] == 6
    assert data["kitchen_slots_before_order"] == 1
    assert data["kitchen_slots_used_by_order"] == 2
    assert fake_service.last_session_token == "session-customer"
    assert fake_service.last_user_email == "customer@zapieapp.pl"


def test_checkout_active_endpoint_returns_null_when_no_active_order():
    client = _build_test_client(_FakeCheckoutServiceActiveEmpty)

    response = client.get(
        "/checkout/active",
        params={
            "session_token": "session-customer",
            "email": "customer@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    assert response.text.strip() == "null"


if __name__ == "__main__":
    test_checkout_active_endpoint_returns_kitchen_diagnostics()
    test_checkout_active_endpoint_returns_null_when_no_active_order()
    print("OK: endpoint test for checkout active")
