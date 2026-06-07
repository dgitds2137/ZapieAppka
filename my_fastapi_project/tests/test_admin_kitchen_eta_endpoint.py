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
from models import AdminCatalogKitchenEtaOverrideUpdateIn
from router import routes


def _admin_catalog_payload(minutes: int) -> dict:
    return {
        "delivery_minimum_amount": 20.0,
        "delivery_radius_km": 8.0,
        "delivery_origin_address": "ul. Test 1",
        "kitchen_eta_override_minutes": minutes,
        "opening_hours": {
            "open_time": "12:00",
            "close_time": "21:00",
            "formatted_range": "12:00-21:00",
            "is_open_now": True,
        },
        "positions": [],
        "addons": [],
    }


class _FakeCheckoutServiceSuccess:
    def __init__(self, db):
        self.db = db
        self.last_payload = None

    def update_kitchen_eta_override(self, payload: AdminCatalogKitchenEtaOverrideUpdateIn):
        self.last_payload = payload
        return _admin_catalog_payload(payload.minutes)


class _FakeCheckoutServiceFailure:
    def __init__(self, db):
        self.db = db

    def update_kitchen_eta_override(self, payload):
        raise HTTPException(
            status_code=400,
            detail="Dopuszczalne wartosci: 0,10,20,30,40 minut.",
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


def test_kitchen_eta_endpoint_success():
    fake_service = _FakeCheckoutServiceSuccess(None)
    client = _build_test_client(lambda db: fake_service)
    response = client.patch(
        "/admin/catalog/kitchen-eta",
        json={
            "minutes": 20,
            "session_token": "token",
            "user_email": "admin@zapieapp.pl",
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["kitchen_eta_override_minutes"] == 20
    assert fake_service.last_payload is not None
    assert fake_service.last_payload.minutes == 20


def test_kitchen_eta_endpoint_rejects_invalid_minutes():
    client = _build_test_client(_FakeCheckoutServiceFailure)
    response = client.patch(
        "/admin/catalog/kitchen-eta",
        json={
            "minutes": 15,
            "session_token": "token",
            "user_email": "admin@zapieapp.pl",
        },
    )
    assert response.status_code == 400
    assert "Dopuszczalne wartosci" in response.text


if __name__ == "__main__":
    test_kitchen_eta_endpoint_success()
    test_kitchen_eta_endpoint_rejects_invalid_minutes()
    print("OK: endpoint test for admin kitchen eta")
