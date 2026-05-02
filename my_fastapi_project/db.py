from pathlib import Path
import re
from threading import Lock

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

MSSQL_CONN_STR = (
    "mssql+pyodbc://danen:Sukiparabuki1@fastfoodapi.database.windows.net:1433/fastfoodapi?loginTimeout=1200&driver=ODBC+Driver+17+for+SQL+Server"
)

engine = create_engine(
    MSSQL_CONN_STR,
    pool_pre_ping=True,
    pool_recycle=1800,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

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

        with engine.begin() as connection:
            sql_dir = Path(__file__).resolve().parent / "sql"
            for script_name in (
                "user_roles.sql",
                "menu_positions.sql",
                "sessions.sql",
                "prep_time_settings.sql",
                "admin_user.sql",
                "employee_user.sql",
                "menu_addons.sql",
                "checkout_orders.sql",
            ):
                script = (sql_dir / script_name).read_text(encoding="utf-8")
                for batch in _split_sql_server_batches(script):
                    connection.exec_driver_sql(batch)

        _schema_ready = True


def get_db():
    ensure_database_schema()
    db = SessionLocal()
    try:
        yield db
    finally: 
        db.close()
