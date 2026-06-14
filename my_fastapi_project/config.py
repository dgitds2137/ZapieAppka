from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - dotenv is optional at import time
    load_dotenv = None

if load_dotenv is not None:
    load_dotenv(Path(__file__).resolve().parent / ".env")
    load_dotenv()


def _csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def _bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def _int(value: str | None, default: int) -> int:
    if value is None:
        return default
    try:
        return int(value.strip())
    except (TypeError, ValueError):
        return default


class Settings:
    def __init__(self) -> None:
        self.app_name = os.getenv("APP_NAME", "ZapieApp API")
        self.environment = os.getenv("APP_ENV", os.getenv("ENVIRONMENT", "local"))
        self.jwt_secret_key = os.getenv("JWT_SECRET_KEY", "dev-local-jwt-secret")
        self.mssql_conn_str = os.getenv("MSSQL_CONN_STR") or os.getenv("DATABASE_URL") or ""
        self.cors_allow_origins = _csv(os.getenv("CORS_ALLOW_ORIGINS"))
        self.cors_allow_origin_regex = os.getenv(
            "CORS_ALLOW_ORIGIN_REGEX",
            r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        )
        self.cors_allow_credentials = _bool(os.getenv("CORS_ALLOW_CREDENTIALS"), True)
        self.require_database_on_startup = _bool(
            os.getenv("REQUIRE_DATABASE_ON_STARTUP"),
            False,
        )
        self.google_auth_client_id = os.getenv("GOOGLE_AUTH_CLIENT_ID", "").strip()
        self.google_auth_client_secret = os.getenv(
            "GOOGLE_AUTH_CLIENT_SECRET",
            "",
        ).strip()
        self.google_auth_default_redirect_uri = os.getenv(
            "GOOGLE_AUTH_DEFAULT_REDIRECT_URI",
            "",
        ).strip()
        self.google_auth_allowed_redirect_uris = _csv(
            os.getenv("GOOGLE_AUTH_ALLOWED_REDIRECT_URIS"),
        )
        self.google_auth_state_ttl_seconds = _int(
            os.getenv("GOOGLE_AUTH_STATE_TTL_SECONDS"),
            600,
        )
        self.apple_auth_client_id = os.getenv("APPLE_AUTH_CLIENT_ID", "").strip()
        self.apple_auth_team_id = os.getenv("APPLE_AUTH_TEAM_ID", "").strip()
        self.apple_auth_key_id = os.getenv("APPLE_AUTH_KEY_ID", "").strip()
        self.apple_auth_private_key = os.getenv("APPLE_AUTH_PRIVATE_KEY", "").strip()
        self.apple_auth_callback_bridge_uri = os.getenv(
            "APPLE_AUTH_CALLBACK_BRIDGE_URI",
            "",
        ).strip()
        self.apple_auth_default_redirect_uri = os.getenv(
            "APPLE_AUTH_DEFAULT_REDIRECT_URI",
            "",
        ).strip()
        self.apple_auth_allowed_redirect_uris = _csv(
            os.getenv("APPLE_AUTH_ALLOWED_REDIRECT_URIS"),
        )
        self.apple_auth_state_ttl_seconds = _int(
            os.getenv("APPLE_AUTH_STATE_TTL_SECONDS"),
            600,
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
