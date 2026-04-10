from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel, EmailStr, ConfigDict
from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    Numeric,
    Boolean,
    Text,
)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()


# =========================
# SQLAlchemy DB models
# =========================

class UserDB(Base):
    __tablename__ = "Users"

    user_id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=True)
    email = Column(String(255), nullable=False, unique=True, index=True)
    password = Column(String(255), nullable=False)
    phone = Column(String(50), nullable=True)
    role = Column(String(50), nullable=True, default="client")
    created_at = Column(DateTime, default=datetime.utcnow)

    orders = relationship("OrderDB", back_populates="user", cascade="all, delete-orphan")
    addresses = relationship("UserAddressDB", back_populates="user", cascade="all, delete-orphan")


class OrderDB(Base):
    __tablename__ = "Orders"

    order_id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True, index=True)
    status = Column(String(20), nullable=True)
    priority = Column(Integer, nullable=True, default=0)
    eta_minutes = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("UserDB", back_populates="orders")
    items = relationship("OrderItemDB", back_populates="order", cascade="all, delete-orphan")
    kitchen_updates = relationship("KitchenUpdateDB", back_populates="order", cascade="all, delete-orphan")


class OrderItemDB(Base):
    __tablename__ = "OrderItems"

    item_id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("Orders.order_id"), nullable=True, index=True)
    product_name = Column(String(100), nullable=True)
    quantity = Column(Integer, nullable=True)
    price = Column(Numeric(10, 2), nullable=True)

    order = relationship("OrderDB", back_populates="items")


class KitchenUpdateDB(Base):
    __tablename__ = "KitchenUpdates"

    update_id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("Orders.order_id"), nullable=True, index=True)
    status = Column(String(20), nullable=True)
    eta_minutes = Column(Integer, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow)

    order = relationship("OrderDB", back_populates="kitchen_updates")


class MenuPositionDB(Base):
    __tablename__ = "MenuPositions"

    position_id = Column(Integer, primary_key=True, index=True)
    position_type = Column(String(50), nullable=True, index=True)
    name = Column(String(80), nullable=True)
    weight = Column(Integer, nullable=True)
    calories = Column(Integer, nullable=True)
    price = Column(Numeric(18, 0), nullable=True)
    description = Column(Text, nullable=True)
    photo_url = Column(String, nullable=True)


class UserAddressDB(Base):
    __tablename__ = "UserAddresses"

    address_id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=False, index=True)
    street = Column(String(200), nullable=False)
    city = Column(String(100), nullable=False)
    postal = Column(String(20), nullable=False)
    phone = Column(String(20), nullable=True)
    is_primary = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("UserDB", back_populates="addresses")


class CheckoutOrderDB(Base):
    __tablename__ = "CheckoutOrders"

    checkout_order_id = Column(Integer, primary_key=True, index=True)
    verification_id = Column(String(32), nullable=False, unique=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True, index=True)
    status = Column(String(50), nullable=False)
    verification_stage = Column(String(50), nullable=False)
    payment_method = Column(String(50), nullable=False)
    currency = Column(String(10), nullable=False)
    total_amount = Column(Numeric(10, 2), nullable=False)
    eta_minutes = Column(Integer, nullable=False)
    fulfillment_method = Column(String(80), nullable=False)
    fulfillment_option_index = Column(Integer, nullable=False)
    address_option_index = Column(Integer, nullable=False)
    address_title = Column(String(200), nullable=False)
    address_subtitle = Column(String(255), nullable=False)
    address_eta_label = Column(String(50), nullable=False)
    notes = Column(Text, nullable=True)
    client_created_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    items = relationship(
        "CheckoutOrderItemDB",
        back_populates="checkout_order",
        cascade="all, delete-orphan",
    )


class CheckoutOrderItemDB(Base):
    __tablename__ = "CheckoutOrderItems"

    checkout_order_item_id = Column(Integer, primary_key=True, index=True)
    checkout_order_id = Column(
        Integer,
        ForeignKey("CheckoutOrders.checkout_order_id"),
        nullable=False,
        index=True,
    )
    cart_entry_id = Column(Integer, nullable=False)
    position_id = Column(Integer, nullable=True)
    name = Column(String(120), nullable=False)
    description = Column(Text, nullable=True)
    photo_url = Column(String(500), nullable=True)
    calories = Column(Integer, nullable=True)
    price = Column(Numeric(10, 2), nullable=True)
    quantity = Column(Integer, nullable=False, default=1)

    checkout_order = relationship("CheckoutOrderDB", back_populates="items")


# =========================
# Pydantic schemas
# =========================

class UserBase(BaseModel):
    name: Optional[str] = None
    email: EmailStr
    phone: Optional[str] = None
    role: Optional[str] = "client"


class UserCreate(UserBase):
    password: str


class UserSchema(UserBase):
    user_id: int
    created_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class OrderItemBase(BaseModel):
    product_name: Optional[str] = None
    quantity: Optional[int] = None
    price: Optional[float] = None


class OrderItemCreate(OrderItemBase):
    pass


class OrderItemSchema(OrderItemBase):
    item_id: int

    model_config = ConfigDict(from_attributes=True)


class OrderBase(BaseModel):
    user_id: Optional[int] = None
    status: Optional[str] = None
    priority: Optional[int] = 0
    eta_minutes: Optional[int] = None


class OrderCreate(OrderBase):
    items: List[OrderItemCreate] = []


class OrderSchema(OrderBase):
    order_id: int
    created_at: Optional[datetime] = None
    items: List[OrderItemSchema] = []

    model_config = ConfigDict(from_attributes=True)


# ===== Compatibility aliases for old imports =====

DeliveryOrderDB = OrderDB
UserAddress = UserAddressDB


class KitchenUpdateCreate(BaseModel):
    order_id: int | None = None
    status: str | None = None
    eta_minutes: int | None = None


class DeliveryOrderIn(BaseModel):
    user_id: int | None = None
    status: str | None = None
    priority: int | None = 0
    eta_minutes: int | None = None


class DeliveryOrderOut(DeliveryOrderIn):
    order_id: int

    model_config = ConfigDict(from_attributes=True)


class GoogleAuthRequest(BaseModel):
    token: str


class AddressCreate(BaseModel):
    user_id: int
    street: str
    city: str
    postal: str
    phone: str | None = None
    is_primary: bool | None = False


class AddressUpdate(BaseModel):
    street: str | None = None
    city: str | None = None
    postal: str | None = None
    phone: str | None = None
    is_primary: bool | None = None


class OrderUpdate(BaseModel):
    status: str | None = None
    priority: int | None = None
    eta_minutes: int | None = None


class OrderItemUpdate(BaseModel):
    product_name: str | None = None
    quantity: int | None = None
    price: float | None = None


class CheckoutItemPayload(BaseModel):
    cart_entry_id: int
    position_id: int | None = None
    name: str
    description: str | None = None
    photo_url: str | None = None
    calories: int | None = None
    price: float | None = None


class CheckoutAddressPayload(BaseModel):
    title: str
    subtitle: str
    eta_label: str


class CheckoutVerificationIn(BaseModel):
    created_at: datetime
    currency: str
    total_amount: float
    eta_minutes: int
    payment_method: str
    fulfillment_method: str
    fulfillment_option_index: int
    address_option_index: int
    address: CheckoutAddressPayload
    items: list[CheckoutItemPayload]
    notes: str | None = None


class CheckoutVerificationOut(BaseModel):
    verification_id: str
    saved_order_id: int
    status: str
    payment_method: str
    verification_stage: str
    message: str
    created_at: datetime
    received_order: CheckoutVerificationIn

class SessionsDB(Base):
    __tablename__ = "Sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=False, index=True)
    session_token = Column(String, nullable=False)
