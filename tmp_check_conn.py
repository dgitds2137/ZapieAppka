import traceback
from sqlalchemy import create_engine

cs = 'mssql+pyodbc://zapieAdmin:Sukiparabuki1!@zapieapp.database.windows.net:1433/zapieapp?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no&loginTimeout=1200'
print('cs=',cs)
engine = create_engine(cs)
try:
    with engine.connect() as conn:
        row = conn.exec_driver_sql('SELECT 1').fetchone()
        print('OK', row)
except Exception:
    traceback.print_exc()
