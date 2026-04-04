from datetime import datetime
from typing import Optional, List
import enum

from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Boolean,
    Enum,
    Text,
    Numeric,
)
from sqlalchemy.orm import declarative_base, relationship, Mapped, mapped_column

Base = declarative_base()


# =========================================================
# ENUMS
# =========================================================

class OrderType(str, enum.Enum):
    delivery = "delivery"
    pickup = "pickup"


class OrderStatus(str, enum.Enum):
    draft = "draft"
    submitted = "submitted"
    accepted = "accepted"
    in_progress = "in_progress"
    ready = "ready"
    completed = "completed"
    cancelled = "cancelled"


# =========================================================
# Pydantic pomocnicze
# =========================================================

class KitchenUpdate(BaseModel):
    order_id: str
    status: str
    eta: int


class Notification(BaseModel):
    user_id: str
    message: str


class OrderRequest(BaseModel):
    user_id: str
    items: list[str]
    priority: bool = False


class GoogleAuthRequest(BaseModel):
    id_token: str


# =========================================================
# SQLAlchemy MODELS
# =========================================================

class KitchenUpdateDB(Base):
    __tablename__ = "KitchenUpdates"

    update_id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, nullable=False)
    status = Column(String, nullable=False)
    eta_minutes = Column(Integer, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow)


class UserAddress(Base):
    __tablename__ = "UserAddresses"

    address_id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("Users.user_id", ondelete="CASCADE", onupdate="CASCADE"),
        nullable=False,
    )
    street = Column(String(200), nullable=False)
    city = Column(String(100), nullable=False)
    postal = Column(String(20), nullable=False)
    phone = Column(String(20), nullable=True)
    is_primary = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("UsersDB", back_populates="addresses")

    # nowy flow /orders
    orders = relationship("Order", back_populates="address")


class MenuPositionDB(Base):
    __tablename__ = "MenuPositions"

    position_id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=True)
    description = Column(String(255), nullable=True)
    photo_url = Column(String(255), nullable=True)

    favorites = relationship(
        "UserFavoritesDB",
        back_populates="menupositions",
        cascade="all, delete-orphan",
    )
    last_orders = relationship(
        "UserLastOrdersDB",
        back_populates="menupositions",
        cascade="all, delete-orphan",
    )

    # relacja dla nowego OrderItem
    order_items = relationship("OrderItem", back_populates="menu_position")


class UserFavoritesDB(Base):
    __tablename__ = "UserFavorites"

    user_id = Column(
        Integer,
        ForeignKey("Users.user_id", ondelete="CASCADE", onupdate="CASCADE"),
        primary_key=True,
    )
    position_id = Column(
        Integer,
        ForeignKey("MenuPositions.position_id", ondelete="CASCADE", onupdate="CASCADE"),
        primary_key=True,
    )

    user = relationship("UsersDB", back_populates="favorites")
    menupositions = relationship("MenuPositionDB", back_populates="favorites")


class UserLastOrdersDB(Base):
    __tablename__ = "UserLastOrders"

    user_id = Column(
        Integer,
        ForeignKey("Users.user_id", ondelete="CASCADE", onupdate="CASCADE"),
        primary_key=True,
    )
    position_id = Column(
        Integer,
        ForeignKey("MenuPositions.position_id", ondelete="CASCADE", onupdate="CASCADE"),
        primary_key=True,
    )
    last_ordered_date = Column(DateTime, default=datetime.utcnow)

    user = relationship("UsersDB", back_populates="last_orders")
    menupositions = relationship("MenuPositionDB", back_populates="last_orders")


class UsersDB(Base):
    __tablename__ = "Users"

    user_id = Column(Integer, primary_key=True, index=True, nullable=False)
    name = Column(String(100), nullable=True)
    email = Column(String(255), nullable=True)
    password = Column(String(500), nullable=True)
    phone = Column(String(50), nullable=True)
    role = Column(String(50), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    favorites = relationship(
        "UserFavoritesDB",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    sessions = relationship("SessionsDB", back_populates="user")
    last_orders = relationship("UserLastOrdersDB", back_populates="user")
    addresses = relationship("UserAddress", back_populates="user")
    orders = relationship("Order", back_populates="user")

class SessionsDB(Base):
    __tablename__ = "Sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=False)
    session_token = Column(String, unique=True, nullable=False)

    user = relationship("UsersDB", back_populates="sessions")


# =========================================================
# NOWY FLOW: orders / order_items
# dopasowany do istniejących tabel MSSQL
# =========================================================

class Order(Base):
    __tablename__ = "Orders"

    order_id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("Users.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    order_type: Mapped[OrderType] = mapped_column(
        Enum(OrderType),
        default=OrderType.pickup,
    )
    address_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("UserAddresses.address_id"),
        nullable=True,
    )
    status: Mapped[OrderStatus] = mapped_column(
        Enum(OrderStatus),
        default=OrderStatus.draft,
    )
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    user = relationship("UsersDB", back_populates="orders")
    address = relationship("UserAddress", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")


class OrderItem(Base):
    __tablename__ = "OrderItems"

    order_item_id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    order_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("Orders.order_id", ondelete="CASCADE"),
        nullable=False,
    )
    menu_position_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("MenuPositions.position_id"),
        nullable=False,
    )
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    price_snapshot: Mapped[float] = mapped_column(Numeric(10, 2), default=0)

    order = relationship("Order", back_populates="items")
    menu_position = relationship("MenuPositionDB", back_populates="order_items")




# =========================================================
# Pydantic SCHEMAS
# =========================================================

class KitchenUpdateCreate(BaseModel):
    order_id: int
    status: str
    eta_minutes: int


class KitchenUpdateOut(BaseModel):
    update_id: int
    order_id: int
    status: str
    eta_minutes: int
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------- Address ----------

class AddressBase(BaseModel):
    street: str
    city: str
    postal: str
    phone: Optional[str] = None
    is_primary: bool = False


class AddressCreate(AddressBase):
    pass


class AddressUpdate(AddressBase):
    pass


class Address(BaseModel):
    address_id: int
    user_id: int
    street: str
    city: str
    postal: str
    phone: Optional[str] = None
    is_primary: bool = False

    model_config = ConfigDict(from_attributes=True)


class AddressSchema(BaseModel):
    address_id: int
    street: str
    city: str
    postal: str
    phone: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


# ---------- Menu ----------

class MenuPositionSchema(BaseModel):
    position_id: int
    name: Optional[str] = None
    description: Optional[str] = None
    photo_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class MenuPositionOut(BaseModel):
    position_id: int
    name: Optional[str] = None
    description: Optional[str] = None
    photo_url: Optional[str] = None
    price: Optional[float] = None

    model_config = ConfigDict(from_attributes=True)


# ---------- Favorites / last orders ----------

class UserFavoriteSchema(BaseModel):
    user_id: int
    position_id: int

    model_config = ConfigDict(from_attributes=True)


class UserLastOrdersSchema(BaseModel):
    user_id: int
    last_ordered_date: datetime
    position_id: int
    menupositions: MenuPositionSchema

    model_config = ConfigDict(from_attributes=True)


# ---------- User ----------

class UserSchema(BaseModel):
    user_id: int
    name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    role: Optional[str] = None

    favorites: List[UserFavoriteSchema] = []
    last_orders: List[UserLastOrdersSchema] = []
    addresses: List[AddressSchema] = []

    model_config = ConfigDict(from_attributes=True)


# ---------- Order item ----------

class OrderItemBase(BaseModel):
    menu_position_id: int
    quantity: int


class OrderItemCreate(OrderItemBase):
    pass


class OrderItemUpdate(BaseModel):
    quantity: int


class OrderItemOut(BaseModel):
    order_item_id: int
    menu_position_id: int
    quantity: int
    price_snapshot: float

    model_config = ConfigDict(from_attributes=True)


# ---------- Order ----------

class OrderBase(BaseModel):
    order_type: OrderType = OrderType.pickup
    address_id: Optional[int] = None
    notes: Optional[str] = None


class OrderCreate(OrderBase):
    pass


class OrderUpdate(BaseModel):
    address_id: Optional[int] = None
    notes: Optional[str] = None
    status: Optional[OrderStatus] = None


class OrderOut(BaseModel):
    order_id: int
    user_id: int
    order_type: OrderType
    status: OrderStatus
    address: Optional[AddressSchema] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    items: List[OrderItemOut] = []

    model_config = ConfigDict(from_attributes=True)


# ---------- Legacy delivery ----------

class DeliveryOrderIn(BaseModel):
    user_id: Optional[int] = None
    status: Optional[str] = None
    priority: Optional[bool] = None
    eta_minutes: Optional[int] = None


class DeliveryOrderOut(BaseModel):
    order_id: int
    user_id: Optional[int] = None
    status: Optional[str] = None
    priority: Optional[bool] = None
    eta_minutes: Optional[int] = None
    created_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class DeliveryOrder(BaseModel):
    customer_name: str = Field(..., example="Jan Kowalski")
    address: str = Field(..., example="ul. Kwiatowa 12, Warszawa")
    phone: str = Field(..., example="+48 123 456 789")
    items: str = Field(..., example="Pizza Margherita x2, Cola x1")
    notes: Optional[str] = Field(None, example="Bez cebuli")

    model_config = ConfigDict(from_attributes=True)