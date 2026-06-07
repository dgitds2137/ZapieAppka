from pathlib import Path
import sys
from unittest.mock import Mock, patch

from fastapi import HTTPException

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from oauth_service import GoogleOAuthService
from models import OAuthCodeExchangeIn


class _FakeUserService:
    last_login = None

    def __init__(self, db):
        self.db = db

    def login_or_register_google_user(self, email: str, name: str | None = None):
        _FakeUserService.last_login = {
            "email": email,
            "name": name,
        }
        return {
            "jwt": "jwt-token",
            "session_token": "session-token",
            "role": "user",
            "user_id": 91,
            "email": email,
            "loyalty_points": 0,
        }


def _make_service():
    _FakeUserService.last_login = None
    service = GoogleOAuthService(Mock(), _FakeUserService)
    service.settings.jwt_secret_key = "test-google-secret"
    service.settings.google_auth_client_id = "google-client-id"
    service.settings.google_auth_client_secret = "google-client-secret"
    service.settings.google_auth_default_redirect_uri = "zapieapp://auth/callback"
    service.settings.google_auth_allowed_redirect_uris = [
        "zapieapp://auth/callback",
        "http://localhost:3000/auth/callback",
    ]
    service.settings.google_auth_state_ttl_seconds = 600
    return service


def test_google_start_returns_signed_state_and_redirect():
    service = _make_service()

    result = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="User@ZapieApp.pl",
    )

    assert result.provider == "google"
    assert result.redirect_uri == "zapieapp://auth/callback"
    assert "accounts.google.com" in result.authorization_url
    decoded_state = service._decode_state(result.state)
    assert decoded_state["provider"] == "google"
    assert decoded_state["redirect_uri"] == "zapieapp://auth/callback"
    assert decoded_state["email"] == "user@zapieapp.pl"


def test_google_start_does_not_require_client_secret():
    service = _make_service()
    service.settings.google_auth_client_secret = ""

    result = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="user@zapieapp.pl",
    )

    assert result.provider == "google"
    assert result.authorization_url


def test_google_start_rejects_unknown_redirect_uri():
    service = _make_service()

    try:
        service.start_authorization(
            redirect_uri="https://evil.example.com/callback",
            email="user@zapieapp.pl",
        )
        raise AssertionError("Expected HTTPException for redirect URI")
    except HTTPException as exc:
        assert exc.status_code == 400
        assert "Redirect URI" in str(exc.detail)


def test_google_callback_exchanges_code_and_uses_verified_email():
    service = _make_service()
    state = service._encode_state(
        redirect_uri="zapieapp://auth/callback",
        email="user@zapieapp.pl",
    )

    with patch.object(service, "_exchange_code_for_tokens") as exchange_mock:
        with patch.object(service, "_fetch_google_profile") as profile_mock:
            exchange_mock.return_value = {
                "access_token": "google-access-token",
            }
            profile_mock.return_value = {
                "email": "user@zapieapp.pl",
                "email_verified": True,
                "name": "User ZapieApp",
            }

            result = service.exchange_code(
                OAuthCodeExchangeIn(
                    code="oauth-code",
                    state=state,
                    redirect_uri="zapieapp://auth/callback",
                    email="user@zapieapp.pl",
                ),
            )

    assert result.email == "user@zapieapp.pl"
    assert result.session_token == "session-token"
    assert _FakeUserService.last_login == {
        "email": "user@zapieapp.pl",
        "name": "User ZapieApp",
    }


def test_google_callback_rejects_unverified_email():
    service = _make_service()
    state = service._encode_state(
        redirect_uri="zapieapp://auth/callback",
        email="user@zapieapp.pl",
    )

    with patch.object(service, "_exchange_code_for_tokens") as exchange_mock:
        with patch.object(service, "_fetch_google_profile") as profile_mock:
            exchange_mock.return_value = {
                "access_token": "google-access-token",
            }
            profile_mock.return_value = {
                "email": "user@zapieapp.pl",
                "email_verified": False,
                "name": "User ZapieApp",
            }

            try:
                service.exchange_code(
                    OAuthCodeExchangeIn(
                        code="oauth-code",
                        state=state,
                        redirect_uri="zapieapp://auth/callback",
                        email="user@zapieapp.pl",
                    ),
                )
                raise AssertionError("Expected HTTPException for unverified email")
            except HTTPException as exc:
                assert exc.status_code == 403
                assert "zweryfikowany" in str(exc.detail)


if __name__ == "__main__":
    test_google_start_returns_signed_state_and_redirect()
    test_google_start_does_not_require_client_secret()
    test_google_start_rejects_unknown_redirect_uri()
    test_google_callback_exchanges_code_and_uses_verified_email()
    test_google_callback_rejects_unverified_email()
    print("OK: test_google_oauth_foundations.py")
