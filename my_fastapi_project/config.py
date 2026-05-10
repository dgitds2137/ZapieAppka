from __future__ import annotations

import os
from functools import lru_cache

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - dotenv is optional at import time
    load_dotenv = None

if load_dotenv is not None:
    load_dotenv()


def _csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def _bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


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


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
