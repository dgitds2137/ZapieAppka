from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlencode
import uuid

import bcrypt
import httpx
import jwt
from fastapi import HTTPException

from config import get_settings
from models import (
    AuthSessionOut,
    GoogleIdTokenExchangeIn,
    OAuthAuthorizationStartOut,
    OAuthCodeExchangeIn,
    UserDB,
)


class GoogleOAuthService:
    _PROVIDER = "google"
    _AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
    _TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
    _USERINFO_ENDPOINT = "https://openidconnect.googleapis.com/v1/userinfo"
    _STATE_PURPOSE = "google-oauth"
    _STATE_ALGORITHM = "HS256"

    def __init__(self, db, user_service_cls):
        self.db = db
        self.user_service_cls = user_service_cls
        self.settings = get_settings()

    def start_authorization(
        self,
        redirect_uri: str,
        email: str | None = None,
    ) -> OAuthAuthorizationStartOut:
        self._ensure_google_start_configured()
        resolved_redirect_uri = self._validate_redirect_uri(redirect_uri)
        normalized_email = self._normalize_email(email)
        state = self._encode_state(
            redirect_uri=resolved_redirect_uri,
            email=normalized_email,
        )
        authorization_url = self._build_authorization_url(
            redirect_uri=resolved_redirect_uri,
            state=state,
            email=normalized_email,
        )
        return OAuthAuthorizationStartOut(
            provider=self._PROVIDER,
            authorization_url=authorization_url,
            redirect_uri=resolved_redirect_uri,
            state=state,
        )

    def exchange_code(
        self,
        payload: OAuthCodeExchangeIn,
    ) -> AuthSessionOut:
        self._ensure_google_callback_configured()
        resolved_redirect_uri = self._validate_redirect_uri(payload.redirect_uri)
        state_data = self._decode_state(payload.state)
        if state_data.get("provider") != self._PROVIDER:
            raise HTTPException(status_code=400, detail="Nieprawidlowy provider logowania.")
        if state_data.get("redirect_uri") != resolved_redirect_uri:
            raise HTTPException(status_code=400, detail="Redirect URI nie zgadza sie ze stanem logowania.")

        token_payload = self._exchange_code_for_tokens(
            code=payload.code,
            redirect_uri=resolved_redirect_uri,
        )
        profile = self._fetch_google_profile(token_payload)

        profile_email = self._normalize_email(profile.get("email"))
        if not profile_email:
            raise HTTPException(status_code=400, detail="Google nie zwrocil adresu e-mail.")
        if profile.get("email_verified") is not True:
            raise HTTPException(
                status_code=403,
                detail="Konto Google musi miec zweryfikowany adres e-mail.",
            )

        hint_email = self._normalize_email(payload.email) or self._normalize_email(
            state_data.get("email"),
        )
        if hint_email and hint_email != profile_email:
            raise HTTPException(
                status_code=400,
                detail="Adres e-mail z logowania nie zgadza sie z odpowiedzia Google.",
            )

        user_service = self.user_service_cls(self.db)
        session_payload = user_service.login_or_register_google_user(
            email=profile_email,
            name=(profile.get("name") or "").strip() or None,
        )
        return AuthSessionOut(**session_payload)

    def exchange_id_token(
        self,
        payload: GoogleIdTokenExchangeIn,
    ) -> AuthSessionOut:
        self._ensure_google_start_configured()
        profile = self._verify_google_id_token(payload.id_token)

        profile_email = self._normalize_email(profile.get("email"))
        if not profile_email:
            raise HTTPException(status_code=400, detail="Google nie zwrocil adresu e-mail.")
        if profile.get("email_verified") is not True:
            raise HTTPException(
                status_code=403,
                detail="Konto Google musi miec zweryfikowany adres e-mail.",
            )

        expected_email = self._normalize_email(payload.email)
        if expected_email and expected_email != profile_email:
            raise HTTPException(
                status_code=400,
                detail="Adres e-mail z logowania nie zgadza sie z odpowiedzia Google.",
            )

        user_service = self.user_service_cls(self.db)
        session_payload = user_service.login_or_register_google_user(
            email=profile_email,
            name=(profile.get("name") or "").strip() or None,
        )
        return AuthSessionOut(**session_payload)

    def _build_authorization_url(
        self,
        redirect_uri: str,
        state: str,
        email: str | None,
    ) -> str:
        params = {
            "client_id": self.settings.google_auth_client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": "openid email profile",
            "state": state,
            "access_type": "offline",
            "prompt": "select_account",
        }
        if email:
            params["login_hint"] = email
        return f"{self._AUTHORIZATION_ENDPOINT}?{urlencode(params)}"

    def _exchange_code_for_tokens(
        self,
        code: str,
        redirect_uri: str,
    ) -> dict[str, Any]:
        try:
            response = httpx.post(
                self._TOKEN_ENDPOINT,
                headers={"Accept": "application/json"},
                data={
                    "code": code,
                    "client_id": self.settings.google_auth_client_id,
                    "client_secret": self.settings.google_auth_client_secret,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                },
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Nie udalo sie polaczyc z Google token endpoint: {exc}",
            ) from exc

        if response.status_code < 200 or response.status_code >= 300:
            detail = self._extract_error_detail(response)
            raise HTTPException(
                status_code=400,
                detail=f"Google odrzucil kod autoryzacyjny: {detail}",
            )

        payload = response.json()
        if not isinstance(payload, dict) or not payload.get("access_token"):
            raise HTTPException(
                status_code=502,
                detail="Google token endpoint zwrocil nieprawidlowy payload.",
            )
        return payload

    def _fetch_google_profile(self, token_payload: dict[str, Any]) -> dict[str, Any]:
        access_token = str(token_payload.get("access_token") or "").strip()
        if not access_token:
            raise HTTPException(
                status_code=502,
                detail="Brakuje access tokena po wymianie kodu Google.",
            )

        try:
            response = httpx.get(
                self._USERINFO_ENDPOINT,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {access_token}",
                },
                timeout=10.0,
            )
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"Nie udalo sie pobrac profilu Google: {exc}",
            ) from exc

        if response.status_code < 200 or response.status_code >= 300:
            detail = self._extract_error_detail(response)
            raise HTTPException(
                status_code=400,
                detail=f"Google userinfo zwrocil blad: {detail}",
            )

        payload = response.json()
        if not isinstance(payload, dict):
            raise HTTPException(
                status_code=502,
                detail="Google userinfo zwrocil nieprawidlowy payload.",
            )
        return payload

    def _verify_google_id_token(self, id_token_value: str) -> dict[str, Any]:
        token = str(id_token_value or "").strip()
        if not token:
            raise HTTPException(status_code=400, detail="Brakuje Google ID tokenu.")
        try:
            from google.auth.transport import requests as google_auth_requests
            from google.oauth2 import id_token as google_id_token
        except ImportError as exc:
            raise HTTPException(
                status_code=503,
                detail=f"Brakuje zaleznosci do weryfikacji Google ID token: {exc}",
            ) from exc

        try:
            payload = google_id_token.verify_oauth2_token(
                token,
                google_auth_requests.Request(),
                self.settings.google_auth_client_id,
            )
        except ValueError as exc:
            raise HTTPException(
                status_code=400,
                detail=f"Google ID token jest nieprawidlowy: {exc}",
            ) from exc

        if not isinstance(payload, dict):
            raise HTTPException(
                status_code=502,
                detail="Google ID token verifier zwrocil nieprawidlowy payload.",
            )
        return payload

    def _ensure_google_start_configured(self) -> None:
        if not self.settings.google_auth_client_id:
            raise HTTPException(
                status_code=503,
                detail="Brakuje konfiguracji GOOGLE_AUTH_CLIENT_ID.",
            )
        if not self._allowed_redirect_uris():
            raise HTTPException(
                status_code=503,
                detail="Brakuje konfiguracji GOOGLE_AUTH_ALLOWED_REDIRECT_URIS.",
            )

    def _ensure_google_callback_configured(self) -> None:
        self._ensure_google_start_configured()
        if not self.settings.google_auth_client_secret:
            raise HTTPException(
                status_code=503,
                detail="Brakuje konfiguracji GOOGLE_AUTH_CLIENT_SECRET.",
            )

    def _allowed_redirect_uris(self) -> list[str]:
        configured = [
            value.strip()
            for value in self.settings.google_auth_allowed_redirect_uris
            if value and value.strip()
        ]
        if self.settings.google_auth_default_redirect_uri:
            default_uri = self.settings.google_auth_default_redirect_uri.strip()
            if default_uri and default_uri not in configured:
                configured.insert(0, default_uri)
        return configured

    def _validate_redirect_uri(self, redirect_uri: str) -> str:
        normalized = (redirect_uri or "").strip()
        if not normalized:
            raise HTTPException(status_code=400, detail="Redirect URI jest wymagany.")
        if normalized not in self._allowed_redirect_uris():
            raise HTTPException(
                status_code=400,
                detail="Redirect URI nie jest dozwolony dla logowania Google.",
            )
        return normalized

    def _encode_state(self, redirect_uri: str, email: str | None) -> str:
        now = datetime.now(timezone.utc)
        exp = now + timedelta(seconds=max(60, self.settings.google_auth_state_ttl_seconds))
        return jwt.encode(
            {
                "provider": self._PROVIDER,
                "purpose": self._STATE_PURPOSE,
                "redirect_uri": redirect_uri,
                "email": email,
                "nonce": str(uuid.uuid4()),
                "iat": int(now.timestamp()),
                "exp": int(exp.timestamp()),
            },
            self.settings.jwt_secret_key,
            algorithm=self._STATE_ALGORITHM,
        )

    def _decode_state(self, state: str) -> dict[str, Any]:
        if not (state or "").strip():
            raise HTTPException(status_code=400, detail="Brakuje state logowania.")
        try:
            payload = jwt.decode(
                state,
                self.settings.jwt_secret_key,
                algorithms=[self._STATE_ALGORITHM],
            )
        except jwt.PyJWTError as exc:
            raise HTTPException(
                status_code=400,
                detail=f"Stan logowania jest nieprawidlowy lub wygasl: {exc}",
            ) from exc
        if payload.get("purpose") != self._STATE_PURPOSE:
            raise HTTPException(status_code=400, detail="Stan logowania ma nieprawidlowy cel.")
        return payload

    def _extract_error_detail(self, response: httpx.Response) -> str:
        try:
            payload = response.json()
        except ValueError:
            return response.text or f"HTTP {response.status_code}"

        if isinstance(payload, dict):
            detail = payload.get("error_description") or payload.get("error")
            if isinstance(detail, str) and detail.strip():
                return detail.strip()
        return response.text or f"HTTP {response.status_code}"

    def _normalize_email(self, email: Any) -> str | None:
        normalized = str(email or "").strip().lower()
        return normalized or None


def build_google_placeholder_password() -> str:
    return bcrypt.hashpw(
        f"google-oauth::{uuid.uuid4()}".encode("utf-8"),
        bcrypt.gensalt(),
    ).decode("utf-8")


def build_google_user_defaults(name: str | None) -> dict[str, Any]:
    return {
        "name": (name or "").strip() or None,
        "password": build_google_placeholder_password(),
    }
