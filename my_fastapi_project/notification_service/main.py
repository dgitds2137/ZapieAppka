from fastapi import FastAPI
from pydantic import BaseModel
from models import Notification

app = FastAPI()

@app.post("/notify")
def notify_user(notification: Notification):
    print(f"Notify {notification.user_id}: {notification.message}")
    return {"status": "sent"}
