from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

MSSQL_CONN_STR = (
    "mssql+pyodbc://danen:Sukiparabuki1@fastfoodapi.database.windows.net:1433/fastfoodapi?loginTimeout=1200&driver=ODBC+Driver+17+for+SQL+Server"
)

engine = create_engine(MSSQL_CONN_STR)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Funkcja zależności dla FastAPI
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally: 
        db.close()
