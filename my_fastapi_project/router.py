from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy.orm import Session
import jwt
from config import get_settings
from models import (
    UserSchema,
    UserCreate,
    MenuAddonSchema,
    OrderCreate,
    OrderSchema,
    OrderItemCreate,
    OrderItemSchema,
    DeliveryOrderOut,
    DeliveryOrderIn,
    AddressCreate,
    AddressUpdate,
    OrderUpdate,
    OrderItemUpdate,
    CheckoutVerificationIn,
    CheckoutHistoryPageOut,
    CheckoutVerificationOut,
    CheckoutReceiptConfirmationIn,
    CheckoutOrderMessageCreateIn,
    CheckoutOrderMessageOut,
    CheckoutOrderMessagesReadIn,
    CheckoutOrderMessagesReadOut,
    AdminCatalogAddonOut,
    AdminCatalogDeliveryMinimumUpdateIn,
    AdminCatalogItemUpdateIn,
    AdminCatalogOut,
    AdminCatalogPositionOut,
    AdminDashboardOut,
    AdminClosedOrdersPageOut,
    AdminDashboardOrderOut,
    AdminOrderStatusUpdateIn,
    PrepTimeSettingOut,
    PrepTimeSettingUpdateIn,
)

import base64
from datetime import datetime, timedelta

SECRET_KEY = get_settings().jwt_secret_key
ALGORITHM = "HS256"

def routes(OrderService, KitchenService, MenuService, UserService, CheckoutService, get_db):
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
        raise HTTPException(
            status_code=501,
            detail=(
                "Google auth nie jest jeszcze skonfigurowany po stronie backendu. "
                "Docelowo endpoint ma weryfikowac token z providera i zwracac standardowa sesje aplikacji."
            ),
        )

    @r.post("/facebook-auth")
    def facebook_auth(access_token: str):
        raise HTTPException(
            status_code=501,
            detail=(
                "Facebook auth nie jest jeszcze skonfigurowany po stronie backendu. "
                "Docelowo endpoint ma weryfikowac token z providera i zwracac standardowa sesje aplikacji."
            ),
        )

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

    @r.get("/position/{position_id}/addons", response_model=list[MenuAddonSchema])
    def get_position_addons(position_id: int, db: Session = Depends(get_db)):
        return MenuService(db).get_position_addons(position_id)
    
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

    @r.post("/checkout/verification", response_model=CheckoutVerificationOut)
    def create_checkout_verification(
        payload: CheckoutVerificationIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).create_checkout_verification(payload)

    @r.get("/checkout/active", response_model=CheckoutVerificationOut | None)
    def get_active_checkout(
        session_token: str | None = None,
        email: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_active_checkout(
            session_token=session_token,
            user_email=email,
        )

    @r.get("/checkout/history", response_model=CheckoutHistoryPageOut)
    def get_checkout_history(
        session_token: str | None = None,
        email: str | None = None,
        page: int = 1,
        page_size: int = 10,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_checkout_history(
            session_token=session_token,
            user_email=email,
            page=page,
            page_size=page_size,
        )

    @r.get("/checkout/delivery-estimate")
    def get_delivery_estimate(db: Session = Depends(get_db)):
        return CheckoutService(db).get_delivery_estimate()

    @r.post("/checkout/confirm-receipt", response_model=CheckoutVerificationOut)
    def confirm_checkout_receipt(
        payload: CheckoutReceiptConfirmationIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).confirm_receipt(payload)

    @r.get(
        "/checkout/orders/{checkout_order_id}/messages",
        response_model=list[CheckoutOrderMessageOut],
    )
    def get_checkout_order_messages(
        checkout_order_id: int,
        session_token: str | None = None,
        email: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_order_messages(
            checkout_order_id=checkout_order_id,
            session_token=session_token,
            user_email=email,
        )

    @r.post(
        "/checkout/orders/{checkout_order_id}/messages",
        response_model=CheckoutOrderMessageOut,
    )
    def create_checkout_order_message(
        checkout_order_id: int,
        payload: CheckoutOrderMessageCreateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).create_order_message(
            checkout_order_id=checkout_order_id,
            payload=payload,
        )

    @r.post(
        "/checkout/orders/{checkout_order_id}/messages/read",
        response_model=CheckoutOrderMessagesReadOut,
    )
    def mark_checkout_order_messages_read(
        checkout_order_id: int,
        payload: CheckoutOrderMessagesReadIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).mark_order_messages_read(
            checkout_order_id=checkout_order_id,
            payload=payload,
        )

    @r.get("/admin/dashboard", response_model=AdminDashboardOut)
    def get_admin_dashboard(
        session_token: str | None = None,
        email: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_admin_dashboard(
            session_token=session_token,
            user_email=email,
        )

    @r.get("/admin/orders/history", response_model=AdminClosedOrdersPageOut)
    def get_admin_closed_orders_history(
        session_token: str | None = None,
        email: str | None = None,
        page: int = 1,
        page_size: int = 15,
        today_only: bool = False,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_admin_closed_orders_history(
            session_token=session_token,
            user_email=email,
            page=page,
            page_size=page_size,
            today_only=today_only,
        )

    @r.get("/admin/catalog", response_model=AdminCatalogOut)
    def get_admin_catalog(
        session_token: str | None = None,
        email: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_admin_catalog(
            session_token=session_token,
            user_email=email,
        )

    @r.patch(
        "/admin/catalog/positions/{position_id}",
        response_model=AdminCatalogPositionOut,
    )
    def update_admin_catalog_position(
        position_id: int,
        payload: AdminCatalogItemUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_admin_catalog_position(
            position_id=position_id,
            payload=payload,
        )

    @r.patch(
        "/admin/catalog/addons/{addon_id}",
        response_model=AdminCatalogAddonOut,
    )
    def update_admin_catalog_addon(
        addon_id: int,
        payload: AdminCatalogItemUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_admin_catalog_addon(
            addon_id=addon_id,
            payload=payload,
        )

    @r.patch(
        "/admin/catalog/delivery-minimum",
        response_model=AdminCatalogOut,
    )
    def update_admin_delivery_minimum(
        payload: AdminCatalogDeliveryMinimumUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_delivery_minimum_amount(
            payload=payload,
        )

    @r.get("/admin/prep-time-settings", response_model=list[PrepTimeSettingOut])
    def get_admin_prep_time_settings(
        session_token: str | None = None,
        email: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_prep_time_settings(
            session_token=session_token,
            user_email=email,
        )

    @r.patch(
        "/admin/prep-time-settings/{group_key}",
        response_model=PrepTimeSettingOut,
    )
    def update_admin_prep_time_setting(
        group_key: str,
        payload: PrepTimeSettingUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_prep_time_setting(
            group_key=group_key,
            payload=payload,
        )

    @r.patch(
        "/admin/orders/{checkout_order_id}/processing-status",
        response_model=AdminDashboardOrderOut,
    )
    def update_admin_order_processing_status(
        checkout_order_id: int,
        payload: AdminOrderStatusUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_admin_order_status(
            checkout_order_id=checkout_order_id,
            payload=payload,
        )
    
    return r
