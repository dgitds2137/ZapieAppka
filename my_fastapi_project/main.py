from contextlib import asynccontextmanager
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.orm import Session, joinedload

from config import get_settings
from db import ensure_database_schema, get_db, get_engine
from checkout_service import CheckoutService
from loyalty import loyalty_points_for_price
from prep_time_config import infer_prep_group_key, prep_group_label
from router import routes

from models import (
    ADMIN_ROLE,
    AddressCreate,
    AddressUpdate,
    DeliveryOrderDB,
    DeliveryOrderIn,
    DeliveryOrderOut,
    DEFAULT_USER_ROLE,
    DRIVER_ROLE,
    EMPLOYEE_ROLE,
    KitchenUpdateCreate,
    KitchenUpdateDB,
    MenuAddonDB,
    MenuPositionDB,
    MenuPositionAddonDB,
    ProductPrepTimeSettingDB,
    OrderCreate,
    OrderDB,
    OrderItemCreate,
    OrderItemDB,
    OrderItemSchema,
    OrderSchema,
    OrderUpdate,
    OrderItemUpdate,
    SessionsDB,
    UserAddress,
    UserCreate,
    UserDB,
    UserSchema,
)
import bcrypt
import jwt
import uuid

settings = get_settings()
SECRET_KEY = settings.jwt_secret_key
ALGORITHM = "HS256"


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.require_database_on_startup:
        ensure_database_schema()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=settings.cors_allow_origin_regex,
    allow_credentials=settings.cors_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount(
    "/assets",
    StaticFiles(directory=Path(__file__).resolve().parent / "assets", check_dir=False),
    name="assets",
)


@app.get("/health")
def health():
    return {
        "status": "ok",
        "app": settings.app_name,
        "environment": settings.environment,
    }


@app.get("/health/db")
def health_db():
    with get_engine().connect() as connection:
        connection.execute(text("SELECT 1"))
    return {"status": "ok", "database": "ok"}

class MenuService:
    def __init__(self, db: Session):
        self.db = db

    def get_all_positions(self):
        settings_by_group = self._get_prep_settings_by_group()
        return [
            self._serialize_position(position, settings_by_group)
            for position in self.db.query(MenuPositionDB)
            .filter(MenuPositionDB.is_active == True)
            .all()
        ]

    def get_position(self, position_id: int):
        position = (
            self.db.query(MenuPositionDB)
            .filter(
                MenuPositionDB.position_id == position_id,
                MenuPositionDB.is_active == True,
            )
            .first()
        )
        if not position:
            raise HTTPException(status_code=404, detail="Menu position not found")
        return self._serialize_position(position, self._get_prep_settings_by_group())

    def get_position_addons(self, position_id: int):
        self.get_position(position_id)

        addons = (
            self.db.query(MenuAddonDB, MenuPositionAddonDB)
            .join(
                MenuPositionAddonDB,
                MenuPositionAddonDB.addon_id == MenuAddonDB.addon_id,
            )
            .filter(
                MenuPositionAddonDB.position_id == position_id,
                MenuAddonDB.is_active == True,
            )
            .order_by(MenuAddonDB.sort_order.asc(), MenuAddonDB.name.asc())
            .all()
        )

        return [
            {
                "addon_id": addon.addon_id,
                "name": addon.name,
                "description": addon.description,
                "price": float(addon.price),
                "photo_url": addon.photo_url,
                "sort_order": addon.sort_order,
                "is_active": addon.is_active,
                "is_default": link.is_default,
                "default_quantity": link.default_quantity,
            }
            for addon, link in addons
        ]

    def _get_prep_settings_by_group(self) -> dict[str, ProductPrepTimeSettingDB]:
        settings = (
            self.db.query(ProductPrepTimeSettingDB)
            .filter(ProductPrepTimeSettingDB.is_active == True)
            .all()
        )
        return {setting.group_key: setting for setting in settings}

    def _serialize_position(
        self,
        position: MenuPositionDB,
        settings_by_group: dict[str, ProductPrepTimeSettingDB],
    ) -> dict[str, object | None]:
        group_key = infer_prep_group_key(position.position_type, position.name)
        setting = settings_by_group.get(group_key) if group_key else None

        return {
            "position_id": position.position_id,
            "position_type": position.position_type,
            "name": position.name,
            "weight": position.weight,
            "calories": position.calories,
            "price": float(position.price) if position.price is not None else None,
            "loyalty_points": loyalty_points_for_price(position.price),
            "description": position.description,
            "photo_url": position.photo_url,
            "is_active": bool(position.is_active),
            "prep_group_key": group_key,
            "prep_group_label": prep_group_label(group_key),
            "prep_minutes": setting.minutes if setting is not None else None,
        }
    
class UserService:
    def __init__(self, db: Session):
        self.db = db
    
    def check_user(self, user_id: int):
        user = self.db.query(UserDB).filter(UserDB.user_id == user_id).first()
        print(user)
        if not user:
            return None
        else: 
            return user
        
    def register(self, email: str, password: str, telephone_number: str, address: str):
        # zahaszuj hasło
        hashed_pwd = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

        # utwórz encję
        new_user = UserDB(
            email=email,
            phone=telephone_number,
            password=hashed_pwd,
            role=DEFAULT_USER_ROLE,
        )

        # zapisz w DB
        self.db.add(new_user)
        self.db.commit()
        self.db.refresh(new_user)

        return new_user
    def get_current_user_id() -> int:
    # NA RAZIE na sztywno – np. user 1
        return 1
    def get_user(self, email: str):
        user = self.db.query(UserDB).filter(UserDB.email == email).first()
        print(user)
        if not user:
            return None
        user_json = UserSchema.model_validate(user).dict()
        user_schema = UserSchema.model_validate(user)


        return user_schema.model_dump()
    
    def get_user_addresses(db: Session, user_id: int) -> list[UserAddress]:
        return (
            db.query(UserAddress)
            .filter(UserAddress.user_id == user_id)
            .order_by(UserAddress.is_default.desc(), UserAddress.id.desc())
            .all()
        )
    
    def create_address(db: Session, user_id: int, data: AddressCreate) -> UserAddress:
        addr = UserAddress(
            user_id=user_id,
            street=data.street,
            building=data.building,
            apartment=data.apartment,
            city=data.city,
            postal_code=data.postal_code,
            label=data.label,
            is_default=data.is_default,
        )
        db.add(addr)
        db.commit()
        db.refresh(addr)

        if data.is_default:
            db.query(models.User).filter(models.User.id == user_id).update(
                {"default_address_id": addr.id}
            )
            db.commit()

        return addr


    def update_address(
        db: Session, address_id: int, user_id: int, data: AddressUpdate
    ) -> UserAddress | None:
        addr = (
            db.query(UserAddress)
            .filter(UserAddress.id == address_id, UserAddress.user_id == user_id)
            .first()
        )
        if not addr:
            return None

        for field, value in data.model_dump().items():
            setattr(addr, field, value)

        db.commit()
        db.refresh(addr)

        if data.is_default:
            db.query(models.User).filter(models.User.id == user_id).update(
                {"default_address_id": addr.id}
            )
            db.commit()

        return addr


    def delete_address(db: Session, address_id: int, user_id: int) -> bool:
        addr = (
            db.query(UserAddress)
            .filter(UserAddress.id == address_id, UserAddress.user_id == user_id)
            .first()
        )
        if not addr:
            return False
        db.delete(addr)
        db.commit()
        return True
    
    def login(self, email: str, password: str):

        user = self.db.query(UserDB).filter(UserDB.email == email).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        normalized_role = self._normalize_role(user.role)
        if user.role != normalized_role:
            user.role = normalized_role
            self.db.commit()
            self.db.refresh(user)
        
        if not bcrypt.checkpw(password.encode("utf-8"), user.password.encode("utf-8")):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        
        jwt_token = jwt.encode({"sub": str(user.user_id)}, SECRET_KEY, algorithm=ALGORITHM)
        session_token = str(uuid.uuid4())

        now = datetime.utcnow()
        new_session = SessionsDB(
            user_id=user.user_id,
            session_token=session_token,
            created_at=now,
            last_seen_at=now,
        )
        self.db.add(new_session)
        self.db.commit()
        self.db.refresh(new_session)
        return {
            "jwt": jwt_token,
            "session_token": session_token,
            "role": normalized_role,
            "user_id": user.user_id,
            "email": user.email,
            "loyalty_points": int(user.loyalty_points or 0),
        }

    def _normalize_role(self, role: str | None) -> str:
        normalized = (role or DEFAULT_USER_ROLE).strip().lower()
        if normalized == "client":
            return DEFAULT_USER_ROLE
        if normalized in {DEFAULT_USER_ROLE, EMPLOYEE_ROLE, DRIVER_ROLE, ADMIN_ROLE}:
            return normalized
        return DEFAULT_USER_ROLE

from sqlalchemy.orm import Session, joinedload

class OrderService:
    def __init__(self, db: Session):
        self.db = db

    def create_order(self, order: DeliveryOrderIn):
        db_order = DeliveryOrderDB(**order.dict())
        self.db.add(db_order)
        self.db.commit()
        self.db.refresh(db_order)
        return db_order

    def get_order(self, order_id: int):
        order = self.db.query(DeliveryOrderDB).filter(DeliveryOrderDB.order_id == order_id).first()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        return order

    def update_order_status(self, order_id: int, status: str):
        order = self.db.query(DeliveryOrderDB).filter(DeliveryOrderDB.id == order_id).first()
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        order.status = status
        self.db.commit()
        self.db.refresh(order)
        return order


    def create_order(db: Session, user_id: int, data: OrderCreate) -> OrderDB:
        order = Order(
            user_id=user_id,
            order_type=data.order_type,
            address_id=data.address_id if data.order_type == OrderType.delivery else None,
            notes=data.notes,
            status=OrderStatus.draft,
        )
        db.add(order)
        db.commit()
        db.refresh(order)
        return order


    def get_order(db: Session, order_id: int, user_id: int | None = None) -> OrderDB | None:
        q = db.query(Order).options(joinedload(Order.items))
        if user_id:
            q = q.filter(Order.user_id == user_id)
        return q.filter(Order.id == order_id).first()


    def update_order(
        db: Session, order: OrderDB, data: OrderUpdate
    ) -> OrderDB:
        if order.status not in [OrderStatus.draft, OrderStatus.submitted]:
            return order  # blokada edycji

        if data.address_id is not None and order.order_type == OrderType.delivery:
            order.address_id = data.address_id
        if data.notes is not None:
            order.notes = data.notes

        db.commit()
        db.refresh(order)
        return order


    def submit_order(db: Session, order: OrderDB) -> OrderDB:
        if order.status == OrderStatus.draft:
            order.status = OrderStatus.submitted
            db.commit()
            db.refresh(order)
        return order


    def add_item_to_order(
        db: Session, order: OrderDB, data: OrderItemCreate
    ) -> OrderItemDB:
        if order.status not in [OrderStatus.draft, OrderStatus.submitted]:
            raise ValueError("Order cannot be modified")

        menu_pos = db.query(models.MenuPosition).filter(
            models.MenuPosition.id == data.menu_position_id
        ).first()
        if not menu_pos:
            raise ValueError("Menu position not found")

        existing_item = next(
            (i for i in order.items if i.menu_position_id == data.menu_position_id),
            None,
        )
        if existing_item:
            existing_item.quantity += data.quantity
            db.commit()
            db.refresh(existing_item)
            return existing_item

        item = OrderItem(
            order_id=order.id,
            menu_position_id=data.menu_position_id,
            quantity=data.quantity,
            price_snapshot=menu_pos.price,
        )
        db.add(item)
        db.commit()
        db.refresh(item)
        return item


    def update_order_item(
        db: Session, order: OrderDB, item_id: int, data: OrderItemUpdate
    ) -> OrderItemDB | None:
        if order.status not in [OrderStatus.draft, OrderStatus.submitted]:
            return None

        item = (
            db.query(OrderItem)
            .filter(OrderItem.id == item_id, OrderItem.order_id == order.id)
            .first()
        )
        if not item:
            return None

        item.quantity = data.quantity
        if item.quantity <= 0:
            db.delete(item)
        db.commit()
        return item


    def delete_order_item(db: Session, order: OrderDB, item_id: int) -> bool:
        if order.status not in [OrderStatus.draft, OrderStatus.submitted]:
            return False

        item = (
            db.query(OrderItem)
            .filter(OrderItem.id == item_id, OrderItem.order_id == order.id)
            .first()
        )
        if not item:
            return False
        db.delete(item)
        db.commit()
        return True


    def get_user_orders(db: Session, user_id: int, limit: int = 20) -> list[OrderDB]:
        return (
            db.query(Order)
            .options(joinedload(Order.items))
            .filter(Order.user_id == user_id)
            .order_by(Order.created_at.desc())
            .limit(limit)
            .all()
        )


    def reorder_from_existing(db: Session, source_order_id: int, user_id: int) -> OrderDB | None:
        source = get_order(db, source_order_id, user_id=user_id)
        if not source:
            return None

        new_order = Order(
            user_id=user_id,
            order_type=source.order_type,
            address_id=source.address_id,
            notes=source.notes,
            status=OrderStatus.draft,
        )
        db.add(new_order)
        db.flush()

        for item in source.items:
            new_item = OrderItem(
                order_id=new_order.id,
                menu_position_id=item.menu_position_id,
                quantity=item.quantity,
                price_snapshot=item.price_snapshot,
            )
            db.add(new_item)

        db.commit()
        db.refresh(new_order)
        return new_order


# KitchenService – logika kuchni
class KitchenService:
    def __init__(self, db: Session):
        self.db = db

    def add_update(self, update: KitchenUpdateCreate):
        db_update = KitchenUpdateDB(**update.dict())
        self.db.add(db_update)
        self.db.commit()
        self.db.refresh(db_update)
        return db_update

    def get_latest_update(self, order_id: int):
        update = (
            self.db.query(KitchenUpdateDB)
            .filter(KitchenUpdateDB.order_id == order_id)
            .order_by(KitchenUpdateDB.updated_at.desc())
            .first()
        )
        if not update:
            raise HTTPException(status_code=404, detail="No updates found for this order")
        return update

# Podpinamy router z orderami
app.include_router(
    routes(
        OrderService,
        KitchenService,
        MenuService,
        UserService,
        CheckoutService,
        get_db,
    )
)
