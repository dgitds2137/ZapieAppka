from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
import uuid

import bcrypt
import jwt
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.orm import Session

from checkout_service import CheckoutService
from config import get_settings
from db import ensure_database_schema, get_db, get_engine
from loyalty import loyalty_points_for_price
from models import (
    ADMIN_ROLE,
    DEFAULT_USER_ROLE,
    DRIVER_ROLE,
    EMPLOYEE_ROLE,
    MenuAddonDB,
    MenuPositionAddonDB,
    MenuPositionDB,
    ProductPrepTimeSettingDB,
    SessionsDB,
    UserDB,
    UserSchema,
)
from prep_time_config import infer_prep_group_key, prep_group_label
from router import routes

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
        self._ensure_required_positions()
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

    def _ensure_required_positions(self) -> None:
        udka_name = "Udka z kurczaka (3 szt.)"
        exists = (
            self.db.query(MenuPositionDB.position_id)
            .filter(MenuPositionDB.name == udka_name)
            .first()
            is not None
        )
        if exists:
            return

        self.db.add(
            MenuPositionDB(
                position_type="udka",
                name=udka_name,
                weight=300,
                calories=600,
                price=20,
                description=(
                    "Pakiet 3 pieczonych udek z kurczaka. "
                    "Kazda kolejna sztuka w koszyku dodaje kolejny pakiet 3 udek."
                ),
                photo_url="assets/images/chickenLeg.png",
                is_active=True,
            )
        )
        self.db.commit()


class UserService:
    def __init__(self, db: Session):
        self.db = db

    def get_user(self, email: str):
        user = self.db.query(UserDB).filter(UserDB.email == email).first()
        if not user:
            return None
        return UserSchema.model_validate(user).model_dump()

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


app.include_router(
    routes(
        MenuService,
        UserService,
        CheckoutService,
        get_db,
    )
)
