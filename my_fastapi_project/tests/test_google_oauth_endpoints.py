from pathlib import Path
import sys
from unittest.mock import Mock

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from main import MenuService, UserService
from models import OAuthCodeExchangeIn
from oauth_router import oauth_routes


class _FakeGoogleOAuthServiceSuccess:
    def __init__(self, db):
        self.db = db
        self.start_calls = []
        self.callback_calls = []

    def start_authorization(self, redirect_uri: str, email: str | None = None):
        self.start_calls.append(
            {
                "redirect_uri": redirect_uri,
                "email": email,
            }
        )
        return {
            "provider": "google",
            "authorization_url": "https://accounts.google.com/o/oauth2/v2/auth?client_id=test",
            "redirect_uri": redirect_uri,
            "state": "signed-state-token",
        }

    def exchange_code(self, payload: OAuthCodeExchangeIn):
        self.callback_calls.append(payload)
        return {
            "jwt": "jwt-token",
            "session_token": "session-token",
            "role": "user",
            "user_id": 15,
            "email": "user@zapieapp.pl",
            "loyalty_points": 0,
        }


class _FakeGoogleOAuthServiceFailure:
    def __init__(self, db):
        self.db = db

    def start_authorization(self, redirect_uri: str, email: str | None = None):
        raise HTTPException(
            status_code=400,
            detail="Redirect URI nie jest dozwolony dla logowania Google.",
        )

    def exchange_code(self, payload: OAuthCodeExchangeIn):
        raise HTTPException(
            status_code=400,
            detail="Stan logowania jest nieprawidlowy lub wygasl.",
        )


def _build_test_client(service_factory):
    def _fake_db():
        yield Mock()

    app = FastAPI()
    app.include_router(
        oauth_routes(
            service_factory,
            _fake_db,
        )
    )
    return TestClient(app)


def test_google_auth_start_endpoint_success():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.get(
        "/google-auth/start",
        params={
            "redirect_uri": "zapieapp://auth/callback",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["provider"] == "google"
    assert data["redirect_uri"] == "zapieapp://auth/callback"
    assert data["state"] == "signed-state-token"
    assert service.start_calls == [
        {
            "redirect_uri": "zapieapp://auth/callback",
            "email": "user@zapieapp.pl",
        }
    ]


def test_google_auth_start_endpoint_failure():
    client = _build_test_client(_FakeGoogleOAuthServiceFailure)

    response = client.get(
        "/google-auth/start",
        params={
            "redirect_uri": "https://evil.example.com/callback",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 400
    assert "Redirect URI" in response.text


def test_google_auth_callback_endpoint_success():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.post(
        "/google-auth/callback",
        json={
            "code": "google-code",
            "state": "signed-state-token",
            "redirect_uri": "zapieapp://auth/callback",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["session_token"] == "session-token"
    assert data["email"] == "user@zapieapp.pl"
    assert len(service.callback_calls) == 1
    assert service.callback_calls[0].code == "google-code"
    assert service.callback_calls[0].redirect_uri == "zapieapp://auth/callback"


def test_google_auth_callback_endpoint_failure():
    client = _build_test_client(_FakeGoogleOAuthServiceFailure)

    response = client.post(
        "/google-auth/callback",
        json={
            "code": "google-code",
            "state": "broken-state",
            "redirect_uri": "zapieapp://auth/callback",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 400
    assert "Stan logowania" in response.text


if __name__ == "__main__":
    test_google_auth_start_endpoint_success()
    test_google_auth_start_endpoint_failure()
    test_google_auth_callback_endpoint_success()
    test_google_auth_callback_endpoint_failure()
    print("OK: test_google_oauth_endpoints.py")
