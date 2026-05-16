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
    UniqueConstraint,
)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

DEFAULT_USER_ROLE = "user"
EMPLOYEE_ROLE = "employee"
DRIVER_ROLE = "driver"
ADMIN_ROLE = "admin"
CHECKOUT_ORDER_STATUS_UNASSIGNED = "unassigned"
CHECKOUT_ORDER_STATUS_ASSIGNED = "assigned"
CHECKOUT_ORDER_STATUS_COMPLETED = "completed"


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
    role = Column(String(50), nullable=True, default=DEFAULT_USER_ROLE)
    loyalty_points = Column(Integer, nullable=False, default=0)
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
    price = Column(Numeric(10, 2), nullable=True)
    description = Column(Text, nullable=True)
    photo_url = Column(String, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)

    addon_links = relationship(
        "MenuPositionAddonDB",
        back_populates="position",
        cascade="all, delete-orphan",
    )


class ProductPrepTimeSettingDB(Base):
    __tablename__ = "ProductPrepTimeSettings"

    setting_id = Column(Integer, primary_key=True, index=True)
    group_key = Column(String(50), nullable=False, unique=True, index=True)
    label = Column(String(120), nullable=False)
    minutes = Column(Integer, nullable=False, default=15)
    sort_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    updated_by_user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class AppRuntimeSettingDB(Base):
    __tablename__ = "AppRuntimeSettings"

    setting_id = Column(Integer, primary_key=True, index=True)
    setting_key = Column(String(80), nullable=False, unique=True, index=True)
    label = Column(String(160), nullable=False)
    decimal_value = Column(Numeric(10, 2), nullable=False, default=0)
    string_value = Column(String(500), nullable=True)
    updated_by_user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class MenuAddonDB(Base):
    __tablename__ = "MenuAddons"

    addon_id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), nullable=False, unique=True, index=True)
    description = Column(Text, nullable=True)
    price = Column(Numeric(10, 2), nullable=False, default=0)
    photo_url = Column(String(500), nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    position_links = relationship(
        "MenuPositionAddonDB",
        back_populates="addon",
        cascade="all, delete-orphan",
    )


class MenuPositionAddonDB(Base):
    __tablename__ = "MenuPositionAddons"
    __table_args__ = (
        UniqueConstraint(
            "position_id",
            "addon_id",
            name="UQ_MenuPositionAddons_position_addon",
        ),
    )

    menu_position_addon_id = Column(Integer, primary_key=True, index=True)
    position_id = Column(
        Integer,
        ForeignKey("MenuPositions.position_id"),
        nullable=False,
        index=True,
    )
    addon_id = Column(
        Integer,
        ForeignKey("MenuAddons.addon_id"),
        nullable=False,
        index=True,
    )
    is_default = Column(Boolean, nullable=False, default=False)
    default_quantity = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    position = relationship("MenuPositionDB", back_populates="addon_links")
    addon = relationship("MenuAddonDB", back_populates="position_links")


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
    assigned_to_user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True, index=True)
    status = Column(String(50), nullable=False)
    processing_status = Column(
        String(50),
        nullable=False,
        default=CHECKOUT_ORDER_STATUS_UNASSIGNED,
    )
    verification_stage = Column(String(50), nullable=False)
    payment_method = Column(String(50), nullable=False)
    currency = Column(String(10), nullable=False)
    subtotal_amount = Column(Numeric(10, 2), nullable=False, default=0)
    total_amount = Column(Numeric(10, 2), nullable=False)
    redeemed_points = Column(Integer, nullable=False, default=0)
    redeemed_amount = Column(Numeric(10, 2), nullable=False, default=0)
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
    assigned_at = Column(DateTime, nullable=True)
    active_until = Column(DateTime, nullable=False)
    receipt_confirmation_requested_at = Column(DateTime, nullable=True)
    receipt_confirmed_at = Column(DateTime, nullable=True)
    support_alert_sent_at = Column(DateTime, nullable=True)
    delivery_extension_count = Column(Integer, nullable=False, default=0)

    items = relationship(
        "CheckoutOrderItemDB",
        back_populates="checkout_order",
        cascade="all, delete-orphan",
    )
    support_alerts = relationship(
        "CheckoutSupportAlertDB",
        back_populates="checkout_order",
        cascade="all, delete-orphan",
    )
    chat_messages = relationship(
        "CheckoutOrderMessageDB",
        back_populates="checkout_order",
        cascade="all, delete-orphan",
        order_by="CheckoutOrderMessageDB.created_at.asc()",
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


class CheckoutSupportAlertDB(Base):
    __tablename__ = "CheckoutSupportAlerts"

    checkout_support_alert_id = Column(Integer, primary_key=True, index=True)
    checkout_order_id = Column(
        Integer,
        ForeignKey("CheckoutOrders.checkout_order_id"),
        nullable=False,
        index=True,
    )
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True, index=True)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    checkout_order = relationship("CheckoutOrderDB", back_populates="support_alerts")


class CheckoutOrderMessageDB(Base):
    __tablename__ = "CheckoutOrderMessages"

    checkout_order_message_id = Column(Integer, primary_key=True, index=True)
    checkout_order_id = Column(
        Integer,
        ForeignKey("CheckoutOrders.checkout_order_id"),
        nullable=False,
        index=True,
    )
    sender_user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=True, index=True)
    sender_role = Column(String(30), nullable=False)
    author_label = Column(String(120), nullable=False)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    staff_read_at = Column(DateTime, nullable=True)

    checkout_order = relationship("CheckoutOrderDB", back_populates="chat_messages")


# =========================
# Pydantic schemas
# =========================

class UserBase(BaseModel):
    name: Optional[str] = None
    email: EmailStr
    phone: Optional[str] = None
    role: Optional[str] = DEFAULT_USER_ROLE
    loyalty_points: int = 0


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


class MenuAddonSchema(BaseModel):
    addon_id: int
    name: str
    description: str | None = None
    price: float
    photo_url: str | None = None
    sort_order: int = 0
    is_active: bool = True
    is_default: bool = False
    default_quantity: int = 0

    model_config = ConfigDict(from_attributes=True)


class AdminCatalogPositionOut(BaseModel):
    position_id: int
    position_type: str | None = None
    name: str
    description: str | None = None
    price: float | None = None
    is_active: bool = True


class AdminCatalogAddonOut(BaseModel):
    addon_id: int
    name: str
    description: str | None = None
    price: float
    sort_order: int = 0
    is_active: bool = True


class OpeningHoursOut(BaseModel):
    open_time: str
    close_time: str
    formatted_range: str
    is_open_now: bool


class AdminCatalogOut(BaseModel):
    delivery_minimum_amount: float
    delivery_radius_km: float
    delivery_origin_address: str
    opening_hours: OpeningHoursOut
    positions: list[AdminCatalogPositionOut]
    addons: list[AdminCatalogAddonOut]


class AdminCatalogItemUpdateIn(BaseModel):
    is_active: bool | None = None
    price: float | None = None
    session_token: str | None = None
    user_email: EmailStr | None = None


class AdminCatalogDeliveryMinimumUpdateIn(BaseModel):
    amount: float
    session_token: str | None = None
    user_email: EmailStr | None = None


class AdminCatalogDeliveryRadiusUpdateIn(BaseModel):
    radius_km: float
    session_token: str | None = None
    user_email: EmailStr | None = None


class AdminCatalogDeliveryOriginAddressUpdateIn(BaseModel):
    address: str
    session_token: str | None = None
    user_email: EmailStr | None = None


class AdminCatalogOpeningHoursUpdateIn(BaseModel):
    open_time: str
    close_time: str
    session_token: str | None = None
    user_email: EmailStr | None = None


class DeliveryAddressValidationIn(BaseModel):
    street: str
    postal: str
    city: str


class DeliveryAddressValidationOut(BaseModel):
    is_within_radius: bool
    distance_km: float
    radius_km: float
    normalized_address: str


class CheckoutPickupLocationOut(BaseModel):
    address: str


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
    subtotal_amount: float | None = None
    total_amount: float
    redeemed_points: int = 0
    redeemed_amount: float = 0
    eta_minutes: int
    payment_method: str
    fulfillment_method: str
    fulfillment_option_index: int
    address_option_index: int
    address: CheckoutAddressPayload
    items: list[CheckoutItemPayload]
    session_token: str | None = None
    user_email: EmailStr | None = None
    notes: str | None = None


class CheckoutPickupSlotEstimateIn(BaseModel):
    items: list[CheckoutItemPayload]


class CheckoutPickupSlotEstimateOut(BaseModel):
    eta_minutes: int
    eta_label: str
    scheduled_pickup_at: datetime


class CheckoutVerificationOut(BaseModel):
    verification_id: str
    saved_order_id: int
    status: str
    processing_status: str = CHECKOUT_ORDER_STATUS_UNASSIGNED
    payment_method: str
    verification_stage: str
    message: str
    created_at: datetime
    active_until: datetime | None = None
    remaining_eta_minutes: int | None = None
    requires_receipt_confirmation: bool = False
    receipt_confirmation_requested_at: datetime | None = None
    support_alert_sent_at: datetime | None = None
    delivery_extension_count: int = 0
    awarded_points: int = 0
    user_points_balance: int = 0
    scheduled_pickup_at: datetime | None = None
    received_order: CheckoutVerificationIn


class CheckoutHistoryPageOut(BaseModel):
    page: int = 1
    page_size: int = 10
    total_count: int = 0
    has_more: bool = False
    orders: list[CheckoutVerificationOut]


class CheckoutReceiptConfirmationIn(BaseModel):
    received: bool
    session_token: str | None = None
    user_email: EmailStr | None = None


class CheckoutOrderMessageCreateIn(BaseModel):
    message: str
    session_token: str | None = None
    user_email: EmailStr | None = None


class CheckoutOrderMessagesReadIn(BaseModel):
    session_token: str | None = None
    user_email: EmailStr | None = None


class CheckoutOrderMessagesReadOut(BaseModel):
    updated_count: int = 0


class CheckoutOrderMessageOut(BaseModel):
    checkout_order_message_id: int
    checkout_order_id: int
    sender_role: str
    author_label: str
    message: str
    created_at: datetime
    staff_read_at: datetime | None = None


class AdminDashboardTurnoverPoint(BaseModel):
    day_label: str
    total_amount: float


class PrepTimeSettingOut(BaseModel):
    group_key: str
    label: str
    minutes: int
    sort_order: int = 0
    is_active: bool = True


class AdminDashboardActiveEmployeeOut(BaseModel):
    user_id: int
    email: str
    display_name: str
    initials: str
    last_seen_at: datetime


class AdminStaffPresencePersonOut(BaseModel):
    user_id: int
    email: str
    display_name: str
    initials: str
    last_seen_at: datetime | None = None
    is_currently_available: bool = False


class AdminStaffPresenceOut(BaseModel):
    currently_available: list[AdminStaffPresencePersonOut]
    recently_available: list[AdminStaffPresencePersonOut]
    all_results: list[AdminStaffPresencePersonOut]


class AdminDashboardOrderItemOut(BaseModel):
    name: str
    quantity: int
    price: float | None = None
    description: str | None = None


class AdminDashboardOrderOut(BaseModel):
    checkout_order_id: int
    verification_id: str
    processing_status: str
    lifecycle_status: str
    verification_stage: str
    created_at: datetime
    closed_at: datetime | None = None
    active_until: datetime | None = None
    remaining_eta_minutes: int = 0
    customer_email: str | None = None
    payment_method: str
    fulfillment_method: str
    total_amount: float
    item_count: int
    item_names: list[str]
    items: list[AdminDashboardOrderItemOut]
    address_title: str
    address_subtitle: str
    notes: str | None = None
    supports_progress_updates: bool = True
    oven_kind: str = "none"
    can_mark_in_oven: bool = True
    oven_slot_count: int = 0
    oven_load: int = 0
    oven_capacity: int = 6
    unread_customer_message_count: int = 0
    assigned_to_me: bool = False
    assigned_operator_email: str | None = None


class AdminDashboardOut(BaseModel):
    logged_in_employee_count: int
    active_employees: list[AdminDashboardActiveEmployeeOut]
    prep_time_settings: list[PrepTimeSettingOut]
    opening_hours: OpeningHoursOut
    oven_load: int = 0
    oven_capacity: int = 6
    udka_oven_load: int = 0
    udka_oven_capacity: int = 16
    udka_slot_label: str = ""
    pending_order_count: int
    in_progress_order_count: int
    new_users_this_month: int
    completed_orders_today: int
    order_history_count: int
    turnover_last_days: list[AdminDashboardTurnoverPoint]
    pending_orders: list[AdminDashboardOrderOut]
    in_progress_orders: list[AdminDashboardOrderOut]
    closed_orders: list[AdminDashboardOrderOut]
    closed_orders_has_more: bool = False
    my_taken_orders: list[AdminDashboardOrderOut]


class AdminClosedOrdersPageOut(BaseModel):
    page: int = 1
    page_size: int = 15
    total_count: int = 0
    has_more: bool = False
    orders: list[AdminDashboardOrderOut]


class AdminOrderStatusUpdateIn(BaseModel):
    processing_status: str
    verification_stage: str | None = None
    session_token: str | None = None
    user_email: EmailStr | None = None


class PrepTimeSettingUpdateIn(BaseModel):
    minutes: int
    session_token: str | None = None
    user_email: EmailStr | None = None

class SessionsDB(Base):
    __tablename__ = "Sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("Users.user_id"), nullable=False, index=True)
    session_token = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_seen_at = Column(DateTime, default=datetime.utcnow, nullable=False)
