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
from models import AdminOrderStatusUpdateIn
from router import routes


def _success_payload() -> dict:
    return {
        "checkout_order_id": 700,
        "verification_id": "phase2-admin-1",
        "processing_status": "assigned",
        "lifecycle_status": "active",
        "verification_stage": "accepted",
        "created_at": "2026-06-14T12:00:00Z",
        "payment_method": "BLIK",
        "fulfillment_method": "odbior",
        "total_amount": 120.0,
        "item_count": 3,
        "item_names": ["Pieczarka 50cm", "Szynka 50cm", "Salame 50cm"],
        "items": [
            {"name": "Pieczarka 50cm", "quantity": 1, "price": 40.0},
            {"name": "Szynka 50cm", "quantity": 1, "price": 40.0},
            {"name": "Salame 50cm", "quantity": 1, "price": 40.0},
        ],
        "address_title": "Sklotowa 6/9",
        "address_subtitle": "Punkt odbioru",
        "remaining_eta_minutes": 15,
        "supports_progress_updates": True,
        "oven_kind": "zapiekanki",
        "can_mark_in_oven": False,
        "oven_slot_count": 3,
        "oven_load": 6,
        "oven_capacity": 6,
        "kitchen_eta_minutes": 15,
        "kitchen_batch_index": 2,
        "kitchen_batch_count": 1,
        "kitchen_capacity": 6,
        "kitchen_current_oven_load": 6,
        "kitchen_queue_pieces_before_order": 4,
        "kitchen_slots_before_order": 1,
        "kitchen_slots_used_by_order": 3,
        "unread_customer_message_count": 2,
        "assigned_to_me": True,
        "assigned_operator_email": "employee@zapieapp.pl",
    }


class _FakeCheckoutServiceSuccess:
    def __init__(self, db):
        self.db = db
        self.last_checkout_order_id = None
        self.last_payload = None

    def update_admin_order_status(
        self,
        checkout_order_id: int,
        payload: AdminOrderStatusUpdateIn,
    ):
        self.last_checkout_order_id = checkout_order_id
        self.last_payload = payload
        return _success_payload()


class _FakeCheckoutServiceConflict:
    def __init__(self, db):
        self.db = db

    def update_admin_order_status(self, checkout_order_id: int, payload):
        raise HTTPException(
            status_code=409,
            detail="To zamowienie nie miesci sie jeszcze w aktualnym wsadzie pieca.",
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


def test_admin_order_processing_status_endpoint_maps_kitchen_diagnostics():
    fake_service = _FakeCheckoutServiceSuccess(None)
    client = _build_test_client(lambda db: fake_service)

    response = client.patch(
        "/admin/orders/700/processing-status",
        json={
            "processing_status": "assigned",
            "verification_stage": "accepted",
            "session_token": "token",
            "user_email": "employee@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["checkout_order_id"] == 700
    assert data["kitchen_eta_minutes"] == 15
    assert data["kitchen_batch_index"] == 2
    assert data["kitchen_batch_count"] == 1
    assert data["kitchen_current_oven_load"] == 6
    assert data["kitchen_queue_pieces_before_order"] == 4
    assert data["kitchen_slots_before_order"] == 1
    assert data["kitchen_slots_used_by_order"] == 3
    assert data["can_mark_in_oven"] is False
    assert fake_service.last_checkout_order_id == 700
    assert fake_service.last_payload is not None
    assert fake_service.last_payload.verification_stage == "accepted"


def test_admin_order_processing_status_endpoint_propagates_in_oven_conflict():
    client = _build_test_client(_FakeCheckoutServiceConflict)

    response = client.patch(
        "/admin/orders/700/processing-status",
        json={
            "processing_status": "assigned",
            "verification_stage": "in_oven",
            "session_token": "token",
            "user_email": "employee@zapieapp.pl",
        },
    )

    assert response.status_code == 409, response.text
    assert "aktualnym wsadzie pieca" in response.text


if __name__ == "__main__":
    test_admin_order_processing_status_endpoint_maps_kitchen_diagnostics()
    test_admin_order_processing_status_endpoint_propagates_in_oven_conflict()
    print("OK: endpoint test for admin order processing status")
