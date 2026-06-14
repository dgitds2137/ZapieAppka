from pathlib import Path
import sys
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlparse

from fastapi import HTTPException

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from oauth_service import AppleOAuthService, GoogleOAuthService
from models import GoogleIdTokenExchangeIn, OAuthCodeExchangeIn


class _FakeUserService:
    last_login = None

    def __init__(self, db):
        self.db = db

    def login_or_register_oauth_user(self, email: str, name: str | None = None):
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


def _make_apple_service():
    _FakeUserService.last_login = None
    service = AppleOAuthService(Mock(), _FakeUserService)
    service.settings.jwt_secret_key = "test-apple-secret"
    service.settings.apple_auth_client_id = "com.zapieapp.web.apple"
    service.settings.apple_auth_team_id = "APPLETEAM123"
    service.settings.apple_auth_key_id = "APPLEKEY123"
    service.settings.apple_auth_private_key = """-----BEGIN PRIVATE KEY-----
TEST-APPLE-PRIVATE-KEY
-----END PRIVATE KEY-----"""
    service.settings.apple_auth_callback_bridge_uri = "https://api.zapieapp.pl/apple-auth/return"
    service.settings.apple_auth_default_redirect_uri = "zapieapp://auth/callback"
    service.settings.apple_auth_allowed_redirect_uris = [
        "zapieapp://auth/callback",
        "http://localhost:3000/auth/callback",
    ]
    service.settings.apple_auth_state_ttl_seconds = 600
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


def test_google_start_without_email_omits_login_hint_and_state_email():
    service = _make_service()

    result = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email=None,
    )

    parsed_url = urlparse(result.authorization_url)
    query = parse_qs(parsed_url.query)

    assert query["redirect_uri"] == ["zapieapp://auth/callback"]
    assert "login_hint" not in query
    decoded_state = service._decode_state(result.state)
    assert decoded_state["email"] is None


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


def test_google_callback_accepts_missing_email_hint_and_uses_google_profile():
    service = _make_service()
    state = service._encode_state(
        redirect_uri="zapieapp://auth/callback",
        email=None,
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
                    email=None,
                ),
            )

    assert result.email == "user@zapieapp.pl"
    assert result.role == "user"
    assert _FakeUserService.last_login == {
        "email": "user@zapieapp.pl",
        "name": "User ZapieApp",
    }


def test_google_callback_rejects_email_mismatch_between_hint_and_google_profile():
    service = _make_service()
    state = service._encode_state(
        redirect_uri="zapieapp://auth/callback",
        email="other@zapieapp.pl",
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

            try:
                service.exchange_code(
                    OAuthCodeExchangeIn(
                        code="oauth-code",
                        state=state,
                        redirect_uri="zapieapp://auth/callback",
                        email=None,
                    ),
                )
                raise AssertionError("Expected HTTPException for mismatched email")
            except HTTPException as exc:
                assert exc.status_code == 400
                assert "nie zgadza" in str(exc.detail)


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


def test_google_mobile_id_token_creates_standard_session():
    service = _make_service()

    with patch.object(service, "_verify_google_id_token") as verify_mock:
        verify_mock.return_value = {
            "email": "user@zapieapp.pl",
            "email_verified": True,
            "name": "User ZapieApp",
        }

        result = service.exchange_id_token(
            GoogleIdTokenExchangeIn(
                id_token="mobile-id-token",
                email="user@zapieapp.pl",
            ),
        )

    assert result.email == "user@zapieapp.pl"
    assert result.session_token == "session-token"
    assert _FakeUserService.last_login == {
        "email": "user@zapieapp.pl",
        "name": "User ZapieApp",
    }


def test_google_mobile_id_token_rejects_email_mismatch():
    service = _make_service()

    with patch.object(service, "_verify_google_id_token") as verify_mock:
        verify_mock.return_value = {
            "email": "user@zapieapp.pl",
            "email_verified": True,
            "name": "User ZapieApp",
        }

        try:
            service.exchange_id_token(
                GoogleIdTokenExchangeIn(
                    id_token="mobile-id-token",
                    email="other@zapieapp.pl",
                ),
            )
            raise AssertionError("Expected HTTPException for mismatched mobile email")
        except HTTPException as exc:
            assert exc.status_code == 400
            assert "nie zgadza" in str(exc.detail)


def test_apple_start_returns_signed_state_and_nonce():
    service = _make_apple_service()

    result = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="User@ZapieApp.pl",
    )

    assert result.provider == "apple"
    assert result.redirect_uri == "zapieapp://auth/callback"
    assert "appleid.apple.com" in result.authorization_url
    assert result.nonce
    decoded_state = service._decode_state(result.state)
    assert decoded_state["provider"] == "apple"
    assert decoded_state["redirect_uri"] == "zapieapp://auth/callback"
    assert decoded_state["email"] == "user@zapieapp.pl"
    assert decoded_state["nonce"] == result.nonce
    parsed_url = urlparse(result.authorization_url)
    query = parse_qs(parsed_url.query)
    assert query["redirect_uri"] == ["https://api.zapieapp.pl/apple-auth/return"]


def test_apple_start_does_not_require_private_key():
    service = _make_apple_service()
    service.settings.apple_auth_team_id = ""
    service.settings.apple_auth_key_id = ""
    service.settings.apple_auth_private_key = ""

    result = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="user@zapieapp.pl",
    )

    assert result.provider == "apple"
    assert result.authorization_url


def test_apple_start_rejects_unknown_redirect_uri():
    service = _make_apple_service()

    try:
        service.start_authorization(
            redirect_uri="https://evil.example.com/callback",
            email="user@zapieapp.pl",
        )
        raise AssertionError("Expected HTTPException for redirect URI")
    except HTTPException as exc:
        assert exc.status_code == 400
        assert "Apple" in str(exc.detail)


def test_apple_callback_exchanges_code_and_uses_verified_email():
    service = _make_apple_service()
    start = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="apple-user@zapieapp.pl",
    )

    with patch.object(service, "_exchange_code_for_tokens") as exchange_mock:
        with patch.object(service, "_verify_apple_id_token") as verify_mock:
            exchange_mock.return_value = {
                "id_token": "apple-id-token",
            }
            verify_mock.return_value = {
                "email": "apple-user@zapieapp.pl",
                "email_verified": "true",
                "nonce": start.nonce,
            }

            result = service.exchange_code(
                OAuthCodeExchangeIn(
                    code="apple-code",
                    state=start.state,
                    redirect_uri="zapieapp://auth/callback",
                    email="apple-user@zapieapp.pl",
                    name="Apple User",
                ),
            )

    assert result.email == "apple-user@zapieapp.pl"
    assert result.session_token == "session-token"
    assert _FakeUserService.last_login == {
        "email": "apple-user@zapieapp.pl",
        "name": "Apple User",
    }


def test_apple_callback_rejects_email_mismatch():
    service = _make_apple_service()
    start = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="other@zapieapp.pl",
    )

    with patch.object(service, "_exchange_code_for_tokens") as exchange_mock:
        with patch.object(service, "_verify_apple_id_token") as verify_mock:
            exchange_mock.return_value = {
                "id_token": "apple-id-token",
            }
            verify_mock.return_value = {
                "email": "apple-user@zapieapp.pl",
                "email_verified": "true",
                "nonce": start.nonce,
            }

            try:
                service.exchange_code(
                    OAuthCodeExchangeIn(
                        code="apple-code",
                        state=start.state,
                        redirect_uri="zapieapp://auth/callback",
                        email=None,
                    ),
                )
                raise AssertionError("Expected HTTPException for mismatched email")
            except HTTPException as exc:
                assert exc.status_code == 400
                assert "Apple" in str(exc.detail)


def test_apple_builds_frontend_callback_redirect_with_user_payload():
    service = _make_apple_service()
    start = service.start_authorization(
        redirect_uri="zapieapp://auth/callback",
        email="apple-user@zapieapp.pl",
    )

    redirect_url = service.build_frontend_callback_redirect(
        state=start.state,
        code="apple-code",
        user='{"email":"apple-user@zapieapp.pl","name":{"firstName":"Apple","lastName":"User"}}',
    )

    parsed = urlparse(redirect_url)
    query = parse_qs(parsed.query)
    assert parsed.scheme == "zapieapp"
    assert query["provider"] == ["apple"]
    assert query["code"] == ["apple-code"]
    assert query["state"] == [start.state]
    assert query["user"] == ['{"email":"apple-user@zapieapp.pl","name":{"firstName":"Apple","lastName":"User"}}']


if __name__ == "__main__":
    test_google_start_returns_signed_state_and_redirect()
    test_google_start_does_not_require_client_secret()
    test_google_start_rejects_unknown_redirect_uri()
    test_google_start_without_email_omits_login_hint_and_state_email()
    test_google_callback_exchanges_code_and_uses_verified_email()
    test_google_callback_accepts_missing_email_hint_and_uses_google_profile()
    test_google_callback_rejects_email_mismatch_between_hint_and_google_profile()
    test_google_callback_rejects_unverified_email()
    test_google_mobile_id_token_creates_standard_session()
    test_google_mobile_id_token_rejects_email_mismatch()
    test_apple_start_returns_signed_state_and_nonce()
    test_apple_start_does_not_require_private_key()
    test_apple_builds_frontend_callback_redirect_with_user_payload()
    test_apple_start_rejects_unknown_redirect_uri()
    test_apple_callback_exchanges_code_and_uses_verified_email()
    test_apple_callback_rejects_email_mismatch()
    print("OK: test_google_oauth_foundations.py")
