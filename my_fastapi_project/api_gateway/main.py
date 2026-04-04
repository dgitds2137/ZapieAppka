from fastapi import FastAPI, Request, Form
import httpx
from models import DeliveryOrder
import OrderService

app = FastAPI()

ORDER_SERVICE_URL = "http://localhost:8001"

@app.post("/order")
async def create_order(request: Request):
    data = await request.json()
    async with httpx.AsyncClient() as client:
        response = await client.post(f"{ORDER_SERVICE_URL}/order", json=data)
    return response.json()

@app.get("/order/{order_id}/status")
async def get_status(order_id: str):
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{ORDER_SERVICE_URL}/order/{order_id}/status")
    return response.json()

@app.post("/order")
def create_order(
    customer_name: str = Form(...),
    address: str = Form(...),
    phone: str = Form(...),
    items: str = Form(...),
    notes: str = Form(None)
):
    order = DeliveryOrder(
        customer_name=customer_name,
        address=address,
        phone=phone,
        items=items,
        notes=notes
    )
    order_id = OrderService.save_order(order)
    return {"order_id": order_id, "status": "received"}