from fastapi import FastAPI
from pydantic import BaseModel
from models import KitchenUpdate

app = FastAPI()
kitchen_queue = {}

@app.post("/update")
def update_order(update: KitchenUpdate):
    kitchen_queue[update.order_id] = {
        "status": update.status,
        "eta": update.eta
    }
    return {"message": "Updated"}
