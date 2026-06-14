from pathlib import Path
import sys
from unittest.mock import Mock

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from main import MenuService, UserService
from models import GoogleIdTokenExchangeIn, OAuthCodeExchangeIn
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

    def exchange_id_token(self, payload: GoogleIdTokenExchangeIn):
        self.callback_calls.append(payload)
        return {
            "jwt": "jwt-token",
            "session_token": "session-token",
            "role": "user",
            "user_id": 15,
            "email": "user@zapieapp.pl",
            "loyalty_points": 0,
        }

    def build_apple_service(self):
        return _FakeAppleOAuthServiceSuccess(self.db)


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

    def exchange_id_token(self, payload: GoogleIdTokenExchangeIn):
        raise HTTPException(
            status_code=400,
            detail="Google ID token jest nieprawidlowy.",
        )

    def build_apple_service(self):
        return _FakeAppleOAuthServiceFailure(self.db)


class _FakeAppleOAuthServiceSuccess:
    def __init__(self, db):
        self.db = db
        self.start_calls = []
        self.callback_calls = []

    def start_authorization(self, redirect_uri: str, email: str | None = None):
        self.start_calls.append({"redirect_uri": redirect_uri, "email": email})
        return {
            "provider": "apple",
            "authorization_url": "https://appleid.apple.com/auth/authorize?client_id=test",
            "redirect_uri": redirect_uri,
            "state": "signed-apple-state-token",
            "nonce": "signed-apple-nonce",
        }

    def exchange_code(self, payload: OAuthCodeExchangeIn):
        self.callback_calls.append(payload)
        return {
            "jwt": "jwt-token",
            "session_token": "session-token",
            "role": "user",
            "user_id": 16,
            "email": "apple-user@zapieapp.pl",
            "loyalty_points": 0,
        }

    def build_frontend_callback_redirect(
        self,
        *,
        state: str,
        code: str | None = None,
        user: str | None = None,
        error: str | None = None,
        error_description: str | None = None,
    ):
        return (
            "zapieapp://auth/callback"
            f"?provider=apple&state={state}"
            f"{'&code=' + code if code else ''}"
        )


class _FakeAppleOAuthServiceFailure:
    def __init__(self, db):
        self.db = db

    def start_authorization(self, redirect_uri: str, email: str | None = None):
        raise HTTPException(
            status_code=400,
            detail="Redirect URI nie jest dozwolony dla logowania Apple.",
        )

    def exchange_code(self, payload: OAuthCodeExchangeIn):
        raise HTTPException(
            status_code=400,
            detail="Stan logowania Apple jest nieprawidlowy lub wygasl.",
        )

    def build_frontend_callback_redirect(
        self,
        *,
        state: str,
        code: str | None = None,
        user: str | None = None,
        error: str | None = None,
        error_description: str | None = None,
    ):
        raise HTTPException(
            status_code=400,
            detail="Stan logowania Apple jest nieprawidlowy lub wygasl.",
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


def test_google_auth_start_endpoint_success_without_email():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.get(
        "/google-auth/start",
        params={
            "redirect_uri": "zapieapp://auth/callback",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["provider"] == "google"
    assert data["redirect_uri"] == "zapieapp://auth/callback"
    assert service.start_calls == [
        {
            "redirect_uri": "zapieapp://auth/callback",
            "email": None,
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
    assert data["jwt"] == "jwt-token"
    assert data["session_token"] == "session-token"
    assert data["role"] == "user"
    assert data["user_id"] == 15
    assert data["email"] == "user@zapieapp.pl"
    assert data["loyalty_points"] == 0
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


def test_google_auth_mobile_endpoint_success():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.post(
        "/google-auth/mobile",
        json={
            "id_token": "mobile-id-token",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["jwt"] == "jwt-token"
    assert data["session_token"] == "session-token"
    assert data["email"] == "user@zapieapp.pl"
    assert len(service.callback_calls) == 1
    assert service.callback_calls[0].id_token == "mobile-id-token"


def test_google_auth_mobile_endpoint_failure():
    client = _build_test_client(_FakeGoogleOAuthServiceFailure)

    response = client.post(
        "/google-auth/mobile",
        json={
            "id_token": "broken-mobile-id-token",
        },
    )

    assert response.status_code == 400
    assert "Google ID token" in response.text


def test_apple_auth_start_endpoint_success():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.get(
        "/apple-auth/start",
        params={
            "redirect_uri": "zapieapp://auth/callback",
            "email": "user@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["provider"] == "apple"
    assert data["redirect_uri"] == "zapieapp://auth/callback"
    assert data["state"] == "signed-apple-state-token"
    assert data["nonce"] == "signed-apple-nonce"


def test_apple_auth_start_endpoint_failure():
    client = _build_test_client(_FakeGoogleOAuthServiceFailure)

    response = client.get(
        "/apple-auth/start",
        params={
            "redirect_uri": "https://evil.example.com/callback",
        },
    )

    assert response.status_code == 400
    assert "Apple" in response.text


def test_apple_auth_callback_endpoint_success():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.post(
        "/apple-auth/callback",
        json={
            "code": "apple-code",
            "state": "signed-apple-state-token",
            "redirect_uri": "zapieapp://auth/callback",
            "email": "apple-user@zapieapp.pl",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()
    assert data["email"] == "apple-user@zapieapp.pl"
    assert data["session_token"] == "session-token"


def test_apple_auth_callback_endpoint_failure():
    client = _build_test_client(_FakeGoogleOAuthServiceFailure)

    response = client.post(
        "/apple-auth/callback",
        json={
            "code": "apple-code",
            "state": "broken-apple-state",
            "redirect_uri": "zapieapp://auth/callback",
        },
    )

    assert response.status_code == 400
    assert "Apple" in response.text


def test_apple_auth_return_endpoint_redirects_to_frontend_callback():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.get(
        "/apple-auth/return",
        params={
            "code": "apple-code",
            "state": "signed-apple-state-token",
        },
        follow_redirects=False,
    )

    assert response.status_code == 302
    assert (
        response.headers["location"]
        == "zapieapp://auth/callback?provider=apple&state=signed-apple-state-token&code=apple-code"
    )


def test_apple_auth_return_post_endpoint_redirects_to_frontend_callback():
    service = _FakeGoogleOAuthServiceSuccess(None)
    client = _build_test_client(lambda db: service)

    response = client.post(
        "/apple-auth/return",
        data={
            "code": "apple-code-post",
            "state": "signed-apple-state-token",
            "user": '{"email":"apple-user@zapieapp.pl"}',
        },
        follow_redirects=False,
    )

    assert response.status_code == 302
    assert (
        response.headers["location"]
        == "zapieapp://auth/callback?provider=apple&state=signed-apple-state-token&code=apple-code-post"
    )


if __name__ == "__main__":
    test_google_auth_start_endpoint_success()
    test_google_auth_start_endpoint_success_without_email()
    test_google_auth_start_endpoint_failure()
    test_google_auth_callback_endpoint_success()
    test_google_auth_callback_endpoint_failure()
    test_google_auth_mobile_endpoint_success()
    test_google_auth_mobile_endpoint_failure()
    test_apple_auth_start_endpoint_success()
    test_apple_auth_start_endpoint_failure()
    test_apple_auth_callback_endpoint_success()
    test_apple_auth_callback_endpoint_failure()
    test_apple_auth_return_endpoint_redirects_to_frontend_callback()
    test_apple_auth_return_post_endpoint_redirects_to_frontend_callback()
    print("OK: test_google_oauth_endpoints.py")
