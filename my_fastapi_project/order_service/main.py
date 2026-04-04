from fastapi import FastAPI
from pydantic import BaseModel
import uuid
from models import OrderRequest, DeliveryOrder, DeliveryOrderDB

app = FastAPI()
orders = {}

@app.post("/order")
def create_order(order: OrderRequest):
    order_id = str(uuid.uuid4())
    orders[order_id] = {
        "status": "received",
        "eta": 20,
        "priority": order.priority
    }
    return {"order_id": order_id}

@app.get("/order/{order_id}/status")
def get_status(order_id: str):
    return orders.get(order_id, {"error": "Not found"})

def save_order(order: DeliveryOrder) -> int:
    db = SessionLocal()
    try:
        db_order = DeliveryOrderDB(**order.dict())
        db.add(db_order)
        db.commit()
        db.refresh(db_order)
        return db_order.id
    finally:
        db.close()