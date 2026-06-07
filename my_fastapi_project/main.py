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
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from checkout_service import CheckoutService
from config import get_settings
from db import ensure_database_schema, get_db, get_engine
from loyalty import loyalty_points_for_price
from models import (
    ADMIN_ROLE,
    AppRuntimeSettingDB,
    CheckoutOrderDB,
    CheckoutOrderMessageDB,
    CheckoutSupportAlertDB,
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
from oauth_router import oauth_routes
from oauth_service import GoogleOAuthService, build_google_user_defaults
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
    _UDKA_SECONDARY_PHOTO_URL_SETTING_KEY = "udka_secondary_photo_url"

    def __init__(self, db: Session):
        self.db = db

    def get_all_positions(self):
        self._ensure_required_positions()
        settings_by_group = self._get_prep_settings_by_group()
        return [
            self._serialize_position(position, settings_by_group)
            for position in self.db.query(MenuPositionDB)
            .order_by(
                MenuPositionDB.position_type.asc(),
                MenuPositionDB.sort_order.asc(),
                MenuPositionDB.name.asc(),
            )
            .all()
            if self._should_expose_position_to_customer(position)
        ]

    def get_position(self, position_id: int):
        position = (
            self.db.query(MenuPositionDB)
            .filter(
                MenuPositionDB.position_id == position_id,
            )
            .first()
        )
        if not position or not self._should_expose_position_to_customer(position):
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
                "addon_group_key": addon.addon_group_key,
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
        secondary_photo_url = (
            self._get_string_runtime_setting(self._UDKA_SECONDARY_PHOTO_URL_SETTING_KEY)
            if group_key == "udka"
            else None
        )

        return {
            "position_id": position.position_id,
            "position_type": position.position_type,
            "sort_order": position.sort_order or 0,
            "name": position.name,
            "weight": position.weight,
            "calories": position.calories,
            "price": float(position.price) if position.price is not None else None,
            "loyalty_points": loyalty_points_for_price(position.price),
            "description": position.description,
            "photo_url": position.photo_url,
            "secondary_photo_url": secondary_photo_url,
            "is_active": bool(position.is_active),
            "prep_group_key": group_key,
            "prep_group_label": prep_group_label(group_key),
            "prep_minutes": setting.minutes if setting is not None else None,
        }

    def _get_string_runtime_setting(self, setting_key: str) -> str | None:
        setting = (
            self.db.query(AppRuntimeSettingDB)
            .filter(AppRuntimeSettingDB.setting_key == setting_key)
            .first()
        )
        value = setting.string_value if setting is not None else None
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    def _should_expose_position_to_customer(self, position: MenuPositionDB) -> bool:
        if self._is_legacy_hidden_position(position):
            return False
        if bool(position.is_active):
            return True
        return self._is_temporarily_unavailable_position(position)

    def _is_legacy_hidden_position(self, position: MenuPositionDB) -> bool:
        position_type = (position.position_type or "").strip().lower()
        name = (position.name or "").strip().lower()
        if "kids" in position_type or "kids" in name:
            return False
        return "25cm" in name

    def _is_temporarily_unavailable_position(self, position: MenuPositionDB) -> bool:
        position_type = (position.position_type or "").strip().lower()
        name = (position.name or "").strip().lower()
        if (
            "frozen" in position_type
            or "mroz" in position_type
            or "vac" in position_type
            or "frozen" in name
            or "mroz" in name
            or "vac" in name
        ):
            return False
        return "zapiek" in position_type or "zapiek" in name

    def _ensure_required_positions(self) -> None:
        udka_name = "Udko z kurczaka - cala noga"
        exists = (
            self.db.query(MenuPositionDB.position_id)
            .filter(MenuPositionDB.position_type == "udka")
            .first()
            is not None
        )
        if exists:
            return

        self.db.add(
            MenuPositionDB(
                position_type="udka",
                sort_order=0,
                name=udka_name,
                weight=300,
                calories=600,
                price=20,
                description=(
                    "Jedna cala noga z kurczaka pieczona na chrupiaco. "
                    "Kazda kolejna sztuka w koszyku dodaje kolejne udko."
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

    def register(
        self,
        email: str,
        password: str,
        name: str | None = None,
        phone: str | None = None,
    ):
        normalized_email = self._normalize_email(email)
        if not normalized_email:
            raise HTTPException(status_code=400, detail="Email is required")

        cleaned_password = password or ""
        if len(cleaned_password) < 8:
            raise HTTPException(
                status_code=400,
                detail="Password must be at least 8 characters",
            )

        existing_user = (
            self.db.query(UserDB)
            .filter(UserDB.email == normalized_email)
            .first()
        )
        if existing_user:
            raise HTTPException(status_code=409, detail="User already exists")

        password_hash = bcrypt.hashpw(
            cleaned_password.encode("utf-8"),
            bcrypt.gensalt(),
        ).decode("utf-8")

        user = UserDB(
            name=(name or "").strip() or None,
            email=normalized_email,
            password=password_hash,
            phone=(phone or "").strip() or None,
            role=DEFAULT_USER_ROLE,
            loyalty_points=0,
        )
        self.db.add(user)

        try:
            self.db.commit()
        except IntegrityError:
            self.db.rollback()
            raise HTTPException(
                status_code=409,
                detail="User already exists",
            ) from None

        self.db.refresh(user)
        return self._create_session_response(user)

    def login(self, email: str, password: str):
        normalized_email = self._normalize_email(email)
        user = (
            self.db.query(UserDB)
            .filter(UserDB.email == normalized_email)
            .first()
        )
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        if not bcrypt.checkpw(
            password.encode("utf-8"),
            user.password.encode("utf-8"),
        ):
            raise HTTPException(status_code=401, detail="Invalid credentials")

        return self._create_session_response(user)

    def login_or_register_google_user(
        self,
        email: str,
        name: str | None = None,
    ):
        normalized_email = self._normalize_email(email)
        if not normalized_email:
            raise HTTPException(status_code=400, detail="Email is required")

        user = (
            self.db.query(UserDB)
            .filter(UserDB.email == normalized_email)
            .first()
        )
        if user is None:
            defaults = build_google_user_defaults(name)
            user = UserDB(
                name=defaults["name"],
                email=normalized_email,
                password=defaults["password"],
                phone=None,
                role=DEFAULT_USER_ROLE,
                loyalty_points=0,
            )
            self.db.add(user)
            try:
                self.db.commit()
            except IntegrityError:
                self.db.rollback()
                user = (
                    self.db.query(UserDB)
                    .filter(UserDB.email == normalized_email)
                    .first()
                )
                if user is None:
                    raise HTTPException(
                        status_code=409,
                        detail="User already exists",
                    ) from None
            else:
                self.db.refresh(user)
        elif (user.name or "").strip() == "" and (name or "").strip():
            user.name = name.strip()
            self.db.commit()
            self.db.refresh(user)

        return self._create_session_response(user)

    def delete_account(self, session_token: str, email: str | None = None):
        session_token = (session_token or "").strip()
        if not session_token:
            raise HTTPException(status_code=401, detail="Session token is required")

        session = (
            self.db.query(SessionsDB)
            .filter(SessionsDB.session_token == session_token)
            .order_by(SessionsDB.last_seen_at.desc(), SessionsDB.id.desc())
            .first()
        )
        if session is None:
            raise HTTPException(status_code=401, detail="Invalid session")

        user = (
            self.db.query(UserDB)
            .filter(UserDB.user_id == session.user_id)
            .first()
        )
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")

        normalized_email = self._normalize_email(email)
        if normalized_email and self._normalize_email(user.email) != normalized_email:
            raise HTTPException(
                status_code=403,
                detail="Session does not match e-mail",
            )

        self._anonymize_user_references(user.user_id)
        self.db.query(SessionsDB).filter(SessionsDB.user_id == user.user_id).delete(
            synchronize_session=False,
        )
        self.db.delete(user)
        self.db.commit()
        return {"status": "deleted"}

    def _anonymize_user_references(self, user_id: int) -> None:
        self.db.query(CheckoutOrderMessageDB).filter(
            CheckoutOrderMessageDB.sender_user_id == user_id,
        ).update({"sender_user_id": None}, synchronize_session=False)
        self.db.query(CheckoutSupportAlertDB).filter(
            CheckoutSupportAlertDB.user_id == user_id,
        ).update({"user_id": None}, synchronize_session=False)
        self.db.query(CheckoutOrderDB).filter(
            CheckoutOrderDB.assigned_to_user_id == user_id,
        ).update({"assigned_to_user_id": None}, synchronize_session=False)
        self.db.query(CheckoutOrderDB).filter(
            CheckoutOrderDB.user_id == user_id,
        ).update({"user_id": None}, synchronize_session=False)

    def _create_session_response(self, user: UserDB):
        normalized_role = self._normalize_role(user.role)
        if user.role != normalized_role:
            user.role = normalized_role
            self.db.commit()
            self.db.refresh(user)

        jwt_token = jwt.encode(
            {"sub": str(user.user_id)},
            SECRET_KEY,
            algorithm=ALGORITHM,
        )
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

    def _normalize_email(self, email: str | None) -> str:
        return (email or "").strip().lower()

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

app.include_router(
    oauth_routes(
        lambda db: GoogleOAuthService(db, UserService),
        get_db,
    )
)
