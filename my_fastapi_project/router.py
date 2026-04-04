from fastapi import APIRouter, Depends, Form
from sqlalchemy.orm import Session
from models import DeliveryOrderIn, DeliveryOrderOut, GoogleAuthRequest, UserSchema, AddressCreate, AddressUpdate, OrderCreate, OrderUpdate, OrderItemCreate, OrderItemUpdate
import base64
from datetime import datetime, timedelta

SECRET_KEY = "supersecret"
ALGORITHM = "HS256"

def routes(OrderService, KitchenService, MenuService, UserService, get_db):
    r = APIRouter()
    def create_jwt(data: dict, expires_delta: timedelta = timedelta(hours=1)):
        to_encode = data.copy()
        expire = datetime.utcnow() + expires_delta
        to_encode.update({"exp": expire})
        return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    @r.post("/orders", response_model=DeliveryOrderOut)
    def create_order(order: DeliveryOrderIn, db: Session = Depends(get_db)):
        return OrderService(db).create_order(order)

    @r.get("/orders/{order_id}")
    def get_order(order_id: int, db: Session = Depends(get_db)):
        return OrderService(db).get_order(order_id)
    
    @r.get("/check_user/{user_id}")
    def check_user(user_id: str, db: Session = Depends(get_db)):
        exists = fingerprint in fake_db
        return UserService(db).check_user(user_id)
    
    @r.post("/login")
    def login(email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
        decoded_pwd = base64.b64decode(password.encode("utf-8")).decode("utf-8")
        
        return UserService(db).login(email, decoded_pwd)
    
    @r.get("/get_user/{email}", response_model=UserSchema)
    def get_user(email: str, db: Session = Depends(get_db)):
        user = UserService(db).get_user(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user   # FastAPI + Pydantic zrobi serializację do JSON

    
    @r.post("/google-auth")
    def google_auth(id_token: str):
        # tu weryfikujesz id_token w Google
        # np. requests.get("https://oauth2.googleapis.com/tokeninfo?id_token=...")

        # przykładowe dane użytkownika
        user = User(id=1, email="test@example.com", name="Daniel")

        # generowanie JWT
        payload = {"sub": user.id, "email": user.email, "name": user.name}
        token = jwt.encode(payload, SECRET_KEY, algorithm="HS256")

        return {"jwt": token, "user": user}

    @r.post("/register")
    def register(email: str = Form(...), 
                password: str = Form(...), 
                telephone_number: str = Form(...), 
                address: str = Form(...), 
                db: Session = Depends(get_db)):
        
        decoded_pwd = base64.b64decode(password.encode("utf-8")).decode("utf-8")
        
        return UserService(db).register(email=email, telephone_number=telephone_number, password=decoded_pwd, address=address)

    @r.get("/position/{position_id}")
    def get_order(position_id: int, db: Session = Depends(get_db)):
        return MenuService(db).get_position(position_id)

    @r.get("/positions")
    def get_(db: Session = Depends(get_db)):
        return MenuService(db).get_all_positions()

    @r.post("/kitchen/{order_id}")
    def prepare_meal(order_id: int, db: Session = Depends(get_db)):
        return KitchenService(db).prepare_meal(order_id)
    
    @r.post("/kitchen/{order_id}/latest")
    def prepare_meal(order_id: int, db: Session = Depends(get_db)):
        return KitchenService(db).get_latest_update(order_id)

    @r.get("/kitchen/status")
    def kitchen_status(db: Session = Depends(get_db)):
        return KitchenService(db).get_kitchen_status()

    # -----------------------------
    # ADDRESSES
    # -----------------------------
    @r.get("/addresses")
    def get_addresses(db: Session = Depends(get_db)):
        return UserService(db).get_addresses()

    @r.post("/addresses")
    def create_address(data: AddressCreate, db: Session = Depends(get_db)):
        return UserService(db).create_address(data)

    @r.put("/addresses/{address_id}")
    def update_address(address_id: int, data: AddressUpdate, db: Session = Depends(get_db)):
        return UserService(db).update_address(address_id, data)

    @r.delete("/addresses/{address_id}")
    def delete_address(address_id: int, db: Session = Depends(get_db)):
        return UserService(db).delete_address(address_id)
       # -----------------------------
    # MENU
    # -----------------------------
    @r.get("/positions")
    def get_positions(db: Session = Depends(get_db)):
        return MenuService(db).get_all_positions()

    @r.get("/position/{position_id}")
    def get_position(position_id: int, db: Session = Depends(get_db)):
        return MenuService(db).get_position(position_id)
    
      # -----------------------------
    # ORDERS
    # -----------------------------
    @r.post("/orders", response_model=DeliveryOrderOut)
    def create_order(order: OrderCreate, db: Session = Depends(get_db)):
        return OrderService(db).create_order(order)

    @r.get("/orders/{order_id}")
    def get_order(order_id: int, db: Session = Depends(get_db)):
        return OrderService(db).get_order(order_id)

    @r.put("/orders/{order_id}")
    def update_order(order_id: int, data: OrderUpdate, db: Session = Depends(get_db)):
        return OrderService(db).update_order(order_id, data)

    @r.post("/orders/{order_id}/submit")
    def submit_order(order_id: int, db: Session = Depends(get_db)):
        return OrderService(db).submit_order(order_id)

    @r.get("/orders/my")
    def get_my_orders(db: Session = Depends(get_db)):
        return OrderService(db).get_my_orders()

    @r.post("/orders/{order_id}/reorder")
    def reorder(order_id: int, db: Session = Depends(get_db)):
        return OrderService(db).reorder(order_id)
    

    # -----------------------------
    # ORDER ITEMS
    # -----------------------------
    @r.post("/orders/{order_id}/items")
    def add_item(order_id: int, data: OrderItemCreate, db: Session = Depends(get_db)):
        return OrderService(db).add_item(order_id, data)

    @r.put("/orders/{order_id}/items/{item_id}")
    def update_item(order_id: int, item_id: int, data: OrderItemUpdate, db: Session = Depends(get_db)):
        return OrderService(db).update_item(order_id, item_id, data)

    @r.delete("/orders/{order_id}/items/{item_id}")
    def delete_item(order_id: int, item_id: int, db: Session = Depends(get_db)):
        return OrderService(db).delete_item(order_id, item_id)
    

    # -----------------------------
    # KITCHEN
    # -----------------------------
    @r.post("/kitchen/{order_id}")
    def kitchen_prepare(order_id: int, db: Session = Depends(get_db)):
        return KitchenService(db).prepare_meal(order_id)

    @r.get("/kitchen/{order_id}/latest")
    def kitchen_latest(order_id: int, db: Session = Depends(get_db)):
        return KitchenService(db).get_latest_update(order_id)

    @r.get("/kitchen/status")
    def kitchen_status(db: Session = Depends(get_db)):
        return KitchenService(db).get_kitchen_status()
    
    return r