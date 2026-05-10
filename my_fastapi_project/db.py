from pathlib import Path
from functools import lru_cache
import re
from threading import Lock

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from config import get_settings


@lru_cache(maxsize=1)
def get_engine():
    conn_str = get_settings().mssql_conn_str
    if not conn_str:
        raise RuntimeError(
            "Brak konfiguracji bazy danych. Ustaw zmienna srodowiskowa MSSQL_CONN_STR "
            "albo DATABASE_URL."
        )

    return create_engine(
        conn_str,
        pool_pre_ping=True,
        pool_recycle=1800,
    )


@lru_cache(maxsize=1)
def get_session_factory():
    return sessionmaker(autocommit=False, autoflush=False, bind=get_engine())

# Funkcja zależności dla FastAPI
_schema_init_lock = Lock()
_schema_ready = False


def _split_sql_server_batches(script: str) -> list[str]:
    return [
        batch.strip()
        for batch in re.split(r"^\s*GO\s*$", script, flags=re.MULTILINE | re.IGNORECASE)
        if batch.strip()
    ]


def ensure_database_schema() -> None:
    global _schema_ready

    if _schema_ready:
        return

    with _schema_init_lock:
        if _schema_ready:
            return

        with get_engine().begin() as connection:
            sql_dir = Path(__file__).resolve().parent / "sql"
            for script_name, required in (
                ("user_roles.sql", True),
                ("menu_positions.sql", True),
                ("sessions.sql", True),
                ("prep_time_settings.sql", True),
                ("app_runtime_settings.sql", True),
                ("admin_user.sql", False),
                ("employee_user.sql", False),
                ("driver_user.sql", False),
                ("menu_addons.sql", True),
                ("checkout_orders.sql", True),
            ):
                script_path = sql_dir / script_name
                if not script_path.exists():
                    if required:
                        raise FileNotFoundError(script_path)
                    continue

                script = script_path.read_text(encoding="utf-8")
                for batch in _split_sql_server_batches(script):
                    connection.exec_driver_sql(batch)

        _schema_ready = True


def get_db():
    ensure_database_schema()
    db = get_session_factory()()
    try:
        yield db
    finally: 
        db.close()
