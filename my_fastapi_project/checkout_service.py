from datetime import datetime, timedelta, timezone
import json
import math
import uuid
from urllib.parse import quote_plus
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy.exc import OperationalError, SQLAlchemyError
from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload

from prep_time_config import infer_prep_group_key
from loyalty import (
    LOYALTY_POINTS_PER_1_PLN,
    loyalty_points_for_order_total,
)
from models import (
    ADMIN_ROLE,
    DRIVER_ROLE,
    EMPLOYEE_ROLE,
    CHECKOUT_ORDER_STATUS_ASSIGNED,
    CHECKOUT_ORDER_STATUS_COMPLETED,
    CHECKOUT_ORDER_STATUS_UNASSIGNED,
    AppRuntimeSettingDB,
    AdminDashboardActiveEmployeeOut,
    AdminCatalogAddonOut,
    AdminCatalogDeliveryMinimumUpdateIn,
    AdminCatalogDeliveryOriginAddressUpdateIn,
    AdminCatalogDeliveryRadiusUpdateIn,
    AdminCatalogItemUpdateIn,
    AdminCatalogOut,
    AdminClosedOrdersPageOut,
    AdminCatalogPositionOut,
    AdminDashboardOrderItemOut,
    AdminDashboardOrderOut,
    AdminDashboardOut,
    AdminDashboardTurnoverPoint,
    AdminOrderStatusUpdateIn,
    AdminStaffPresenceOut,
    AdminStaffPresencePersonOut,
    CheckoutOrderMessageCreateIn,
    CheckoutOrderMessageDB,
    CheckoutOrderMessageOut,
    CheckoutOrderMessagesReadIn,
    CheckoutOrderMessagesReadOut,
    CheckoutOrderDB,
    CheckoutOrderItemDB,
    CheckoutSupportAlertDB,
    CheckoutVerificationIn,
    CheckoutHistoryPageOut,
    CheckoutVerificationOut,
    CheckoutPickupSlotEstimateIn,
    CheckoutPickupLocationOut,
    CheckoutPickupSlotEstimateOut,
    CheckoutReceiptConfirmationIn,
    CheckoutAddressPayload,
    DeliveryAddressValidationIn,
    DeliveryAddressValidationOut,
    CheckoutItemPayload,
    MenuAddonDB,
    MenuPositionDB,
    PrepTimeSettingOut,
    PrepTimeSettingUpdateIn,
    ProductPrepTimeSettingDB,
    SessionsDB,
    UserDB,
)


class CheckoutService:
    _EMPLOYEE_ACTIVITY_WINDOW = timedelta(minutes=5)
    _SESSION_TOUCH_INTERVAL = timedelta(seconds=30)
    _STANDARD_DELIVERY_ETA_MINUTES = 30
    _BUSY_DELIVERY_ETA_MINUTES = 60
    _OVEN_CAPACITY = 6
    _UDKA_OVEN_CAPACITY = 16
    _UDKA_PIECES_PER_ITEM = 3
    _OVEN_QUEUE_DELAY_MINUTES = 8
    _CHECKOUT_HISTORY_DEFAULT_PAGE_SIZE = 10
    _CHECKOUT_HISTORY_MAX_PAGE_SIZE = 25
    _ADMIN_CLOSED_ORDERS_PREVIEW_LIMIT = 8
    _ADMIN_HISTORY_DEFAULT_PAGE_SIZE = 15
    _ADMIN_HISTORY_MAX_PAGE_SIZE = 30
    _DEFAULT_DELIVERY_MINIMUM_AMOUNT = 20.0
    _DELIVERY_MINIMUM_SETTING_KEY = "delivery_minimum_amount"
    _DEFAULT_DELIVERY_RADIUS_KM = 8.0
    _DELIVERY_RADIUS_SETTING_KEY = "delivery_radius_km"
    _DELIVERY_ORIGIN_ADDRESS_SETTING_KEY = "delivery_origin_address"
    _DELIVERY_IN_PROGRESS_STAGES = {
        "on_the_way",
        "delivery_started",
        "delivery_extended",
        "awaiting_receipt_confirmation",
    }
    _NOMINATIM_SEARCH_URL = "https://nominatim.openstreetmap.org/search"
    _NOMINATIM_USER_AGENT = "ZapieApp/1.0 (delivery-radius-validation)"
    _PICKUP_SLOT_HOURS = (12, 15, 18)
    _PICKUP_SLOT_TIMEZONE = ZoneInfo("Europe/Warsaw")

    _METHOD_MESSAGES = {
        "BLIK": "Platnosc BLIK zostala zasymulowana jako udana. Zamowienie jest aktywne.",
        "Google Pay": "Platnosc Google Pay zostala zasymulowana jako udana. Zamowienie jest aktywne.",
        "Apple Pay": "Platnosc Apple Pay zostala zasymulowana jako udana. Zamowienie jest aktywne.",
    }

    def __init__(self, db: Session):
        self.db = db

    def _as_utc(self, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def _as_naive_utc(self, value: datetime | None) -> datetime | None:
        utc_value = self._as_utc(value)
        if utc_value is None:
            return None
        return utc_value.replace(tzinfo=None)

    def create_checkout_verification(
        self,
        payload: CheckoutVerificationIn,
    ) -> CheckoutVerificationOut:
        verification_id = f"chk_{uuid.uuid4().hex[:12]}"
        created_at = datetime.utcnow()
        self._ensure_checkout_items_are_available(payload.items)
        checkout_positions = self._resolve_checkout_positions(payload.items)
        if self._contains_udka_positions(checkout_positions) and not self._is_planned_pickup_fulfillment(
            payload.fulfillment_method,
            payload.fulfillment_option_index,
        ):
            raise HTTPException(
                status_code=409,
                detail=(
                    "Udka z kurczaka sa dostepne tylko w opcji Zaplanuj odbior "
                    "w transzach 12:00, 15:00 i 18:00."
                ),
            )
        pickup_slot_datetime = None
        if self._is_pickup_slot_order(
            positions=checkout_positions,
            fulfillment_method=payload.fulfillment_method,
            fulfillment_option_index=payload.fulfillment_option_index,
        ):
            pickup_slot_datetime = self._resolve_pickup_slot_datetime(
                now=created_at,
                positions=checkout_positions,
            )
        effective_eta_minutes = self._calculate_checkout_eta_minutes(
            payload.items,
            fallback_minutes=payload.eta_minutes,
            fulfillment_method=payload.fulfillment_method,
            fulfillment_option_index=payload.fulfillment_option_index,
            now=created_at,
            positions=checkout_positions,
            pickup_slot_datetime=pickup_slot_datetime,
        )
        effective_address = payload.address
        pickup_location_address = self._get_delivery_origin_address().strip()
        if self._is_delivery_fulfillment(
            payload.fulfillment_method,
            payload.fulfillment_option_index,
        ):
            effective_address = payload.address.model_copy(
                update={"eta_label": self._delivery_eta_label(effective_eta_minutes)}
            )
        elif self._is_pickup_slot_order(
            positions=checkout_positions,
            fulfillment_method=payload.fulfillment_method,
            fulfillment_option_index=payload.fulfillment_option_index,
        ):
            effective_address = payload.address.model_copy(
                update={
                    "title": pickup_location_address or payload.address.title,
                    "subtitle": payload.fulfillment_method,
                    "eta_label": self._pickup_slot_eta_label(
                        now=created_at,
                        slot_datetime=pickup_slot_datetime,
                    ),
                }
            )
        else:
            effective_address = payload.address.model_copy(
                update={
                    "title": pickup_location_address or payload.address.title,
                    "subtitle": payload.fulfillment_method,
                }
            )
        active_until = (
            self._as_naive_utc(pickup_slot_datetime)
            if pickup_slot_datetime is not None
            else created_at + timedelta(minutes=max(effective_eta_minutes, 1))
        )
        user_id = self._resolve_user_id(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )
        user = (
            self.db.query(UserDB).filter(UserDB.user_id == user_id).first()
            if user_id is not None
            else None
        )
        subtotal_amount = self._calculate_checkout_subtotal_amount(payload.items)
        redeemed_points, redeemed_amount = self._resolve_redeemed_points(
            user=user,
            requested_points=payload.redeemed_points,
            subtotal_amount=subtotal_amount,
        )
        effective_total_amount = max(0.0, round(subtotal_amount - redeemed_amount, 2))
        if self._is_delivery_fulfillment(
            payload.fulfillment_method,
            payload.fulfillment_option_index,
        ):
            minimum_delivery_amount = self._get_delivery_minimum_amount()
            if subtotal_amount < minimum_delivery_amount:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Minimalna wartosc zamowienia z dostawa to "
                        f"PLN {minimum_delivery_amount:.2f}. "
                        "Dodaj kolejne pozycje albo wybierz odbior osobisty."
                    ),
                )
        awarded_points = (
            loyalty_points_for_order_total(subtotal_amount)
            if user is not None
            else 0
        )

        checkout_order = CheckoutOrderDB(
            verification_id=verification_id,
            user_id=user_id,
            status="active",
            processing_status=CHECKOUT_ORDER_STATUS_UNASSIGNED,
            verification_stage="accepted",
            payment_method=payload.payment_method,
            currency=payload.currency,
            subtotal_amount=subtotal_amount,
            total_amount=effective_total_amount,
            redeemed_points=redeemed_points,
            redeemed_amount=redeemed_amount,
            eta_minutes=effective_eta_minutes,
            fulfillment_method=payload.fulfillment_method,
            fulfillment_option_index=payload.fulfillment_option_index,
            address_option_index=payload.address_option_index,
            address_title=effective_address.title,
            address_subtitle=effective_address.subtitle,
            address_eta_label=effective_address.eta_label,
            notes=payload.notes,
            client_created_at=payload.created_at,
            created_at=created_at,
            active_until=active_until,
        )

        try:
            self.db.add(checkout_order)
            self.db.flush()

            for item in payload.items:
                self.db.add(
                    CheckoutOrderItemDB(
                        checkout_order_id=checkout_order.checkout_order_id,
                        cart_entry_id=item.cart_entry_id,
                        position_id=item.position_id,
                        name=item.name,
                        description=item.description,
                        photo_url=item.photo_url,
                        calories=item.calories,
                        price=item.price,
                        quantity=1,
                    )
                )

            if user is not None:
                user.loyalty_points = max(
                    0,
                    int(user.loyalty_points or 0) - redeemed_points + awarded_points,
                )

            self.db.commit()
            self.db.refresh(checkout_order)
        except SQLAlchemyError as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail="Nie udalo sie zapisac zamowienia checkout.",
            ) from exc

        response_payload = payload.model_copy(
            update={
                "subtotal_amount": subtotal_amount,
                "total_amount": effective_total_amount,
                "redeemed_points": redeemed_points,
                "redeemed_amount": redeemed_amount,
                "eta_minutes": effective_eta_minutes,
                "address": effective_address,
            },
        )

        return CheckoutVerificationOut(
            verification_id=verification_id,
            saved_order_id=checkout_order.checkout_order_id,
            status=checkout_order.status,
            processing_status=checkout_order.processing_status,
            payment_method=payload.payment_method,
            verification_stage=checkout_order.verification_stage,
            message=self._METHOD_MESSAGES.get(
                payload.payment_method,
                "Platnosc zostala przyjeta w trybie symulacji i zamowienie jest aktywne.",
            ),
            created_at=self._as_utc(checkout_order.created_at),
            active_until=self._as_utc(checkout_order.active_until),
            remaining_eta_minutes=effective_eta_minutes,
            awarded_points=awarded_points,
            user_points_balance=int(user.loyalty_points or 0) if user is not None else 0,
            scheduled_pickup_at=self._as_utc(pickup_slot_datetime),
            received_order=response_payload,
        )

    def get_delivery_estimate(self) -> dict[str, int | bool]:
        has_delivery_in_progress = self._has_delivery_in_progress(datetime.utcnow())
        eta_minutes = (
            self._BUSY_DELIVERY_ETA_MINUTES
            if has_delivery_in_progress
            else self._STANDARD_DELIVERY_ETA_MINUTES
        )
        return {
            "eta_minutes": eta_minutes,
            "has_delivery_in_progress": has_delivery_in_progress,
        }

    def get_pickup_location(self) -> CheckoutPickupLocationOut:
        return CheckoutPickupLocationOut(
            address=self._get_delivery_origin_address(),
        )

    def get_pickup_slot_estimate(
        self,
        payload: CheckoutPickupSlotEstimateIn,
    ) -> CheckoutPickupSlotEstimateOut:
        self._ensure_checkout_items_are_available(payload.items)
        checkout_positions = self._resolve_checkout_positions(payload.items)
        if not self._contains_udka_positions(checkout_positions):
            raise HTTPException(
                status_code=409,
                detail="Ten podglad transzy dotyczy wyłącznie zamowien z udkami.",
            )

        now = datetime.utcnow()
        pickup_slot_datetime = self._resolve_pickup_slot_datetime(
            now=now,
            positions=checkout_positions,
        )
        return CheckoutPickupSlotEstimateOut(
            eta_minutes=self._pickup_slot_eta_minutes(
                now=now,
                slot_datetime=pickup_slot_datetime,
            ),
            eta_label=self._pickup_slot_eta_label(
                now=now,
                slot_datetime=pickup_slot_datetime,
            ),
            scheduled_pickup_at=self._as_utc(pickup_slot_datetime),
        )

    def get_admin_dashboard(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
    ) -> AdminDashboardOut:
        current_user = self._require_admin_user(
            session_token=session_token,
            user_email=user_email,
        )

        now = datetime.utcnow()
        normalized_role = (current_user.role or "").strip().lower()
        is_employee_view = normalized_role == EMPLOYEE_ROLE
        is_driver_view = normalized_role == DRIVER_ROLE
        is_limited_staff_view = normalized_role in {EMPLOYEE_ROLE, DRIVER_ROLE}
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        turnover_start = day_start - timedelta(days=4)
        active_employees = [] if is_limited_staff_view else self._get_active_employees(now=now)
        current_oven_load = self._get_current_oven_load()
        next_udka_slot = self._next_pickup_slot_datetime(now=now)
        current_udka_oven_load = self._get_udka_slot_load(next_udka_slot)
        active_checkout_rows = (
            self.db.query(CheckoutOrderDB, UserDB.email)
            .outerjoin(UserDB, UserDB.user_id == CheckoutOrderDB.user_id)
            .options(
                joinedload(CheckoutOrderDB.items),
                joinedload(CheckoutOrderDB.chat_messages),
            )
            .filter(
                or_(
                    CheckoutOrderDB.status != "completed",
                    CheckoutOrderDB.processing_status != CHECKOUT_ORDER_STATUS_COMPLETED,
                ),
            )
            .order_by(CheckoutOrderDB.created_at.desc())
            .all()
        )

        pending_orders: list[AdminDashboardOrderOut] = []
        in_progress_orders: list[AdminDashboardOrderOut] = []
        my_taken_orders: list[AdminDashboardOrderOut] = []
        closed_orders_query = self._closed_orders_query(
            current_user=current_user,
            normalized_role=normalized_role,
        )
        order_history_count = closed_orders_query.count()
        closed_preview_rows = (
            closed_orders_query
            .outerjoin(UserDB, UserDB.user_id == CheckoutOrderDB.user_id)
            .options(
                joinedload(CheckoutOrderDB.items),
                joinedload(CheckoutOrderDB.chat_messages),
            )
            .order_by(self._closed_orders_sort_expression().desc())
            .limit(self._ADMIN_CLOSED_ORDERS_PREVIEW_LIMIT)
            .all()
        )
        recent_closed_metric_rows = (
            self._closed_orders_query(
                current_user=current_user,
                normalized_role=normalized_role,
            )
            .options(
                joinedload(CheckoutOrderDB.items),
                joinedload(CheckoutOrderDB.chat_messages),
            )
            .filter(
                or_(
                    CheckoutOrderDB.receipt_confirmed_at >= turnover_start,
                    CheckoutOrderDB.active_until >= turnover_start,
                    CheckoutOrderDB.assigned_at >= turnover_start,
                    CheckoutOrderDB.created_at >= turnover_start,
                ),
            )
            .all()
        )
        completed_orders_today = 0
        assigned_user_ids = {
            checkout_order.assigned_to_user_id
            for checkout_order, _ in active_checkout_rows
            if checkout_order.assigned_to_user_id is not None
        }
        assigned_user_ids.update(
            checkout_order.assigned_to_user_id
            for checkout_order in closed_preview_rows
            if checkout_order.assigned_to_user_id is not None
        )
        assigned_user_emails = {
            user.user_id: user.email
            for user in self.db.query(UserDB).filter(UserDB.user_id.in_(assigned_user_ids)).all()
        } if assigned_user_ids else {}

        turnover_by_day = {
            (day_start - timedelta(days=offset)).date(): 0.0 for offset in range(4, -1, -1)
        }

        for checkout_order in recent_closed_metric_rows:
            closed_at = self._resolve_closed_at(checkout_order)
            if closed_at is not None and closed_at >= turnover_start:
                turnover_day = closed_at.date()
                if turnover_day in turnover_by_day:
                    turnover_by_day[turnover_day] += 1

            if is_limited_staff_view:
                continue

            if closed_at is not None and closed_at >= day_start:
                completed_orders_today += 1

        closed_orders = [
            self._build_admin_order(
                checkout_order,
                customer_email=None,
                now=now,
                current_user_id=current_user.user_id,
                assigned_operator_email=assigned_user_emails.get(
                    checkout_order.assigned_to_user_id,
                ),
                current_oven_load=current_oven_load,
                current_udka_oven_load=current_udka_oven_load,
            )
            for checkout_order in closed_preview_rows
        ]

        for checkout_order, customer_email in active_checkout_rows:
            if is_driver_view and not self._is_driver_order(checkout_order):
                continue

            if not self._is_order_visible_on_admin_board(checkout_order):
                continue

            dashboard_order = self._build_admin_order(
                checkout_order,
                customer_email=customer_email,
                now=now,
                current_user_id=current_user.user_id,
                assigned_operator_email=assigned_user_emails.get(
                    checkout_order.assigned_to_user_id,
                ),
                current_oven_load=current_oven_load,
                current_udka_oven_load=current_udka_oven_load,
            )
            is_ready_for_delivery = self._is_ready_for_delivery_stage(checkout_order)

            if is_driver_view:
                if is_ready_for_delivery:
                    pending_orders.append(dashboard_order)
                elif checkout_order.processing_status == CHECKOUT_ORDER_STATUS_ASSIGNED:
                    if dashboard_order.assigned_to_me:
                        in_progress_orders.append(dashboard_order)
                        my_taken_orders.append(dashboard_order)
            else:
                if (
                    checkout_order.processing_status == CHECKOUT_ORDER_STATUS_ASSIGNED
                    or is_ready_for_delivery
                ):
                    in_progress_orders.append(dashboard_order)
                    if dashboard_order.assigned_to_me:
                        my_taken_orders.append(dashboard_order)
                else:
                    pending_orders.append(dashboard_order)

        logged_in_employee_count = len(active_employees)
        new_users_this_month = (
            self.db.query(UserDB)
            .filter(UserDB.created_at >= month_start)
            .count()
        )

        turnover_last_days = [
            AdminDashboardTurnoverPoint(
                day_label=day.strftime("%d.%m"),
                total_amount=round(total, 2),
            )
            for day, total in sorted(turnover_by_day.items())
        ] if not is_limited_staff_view else []

        return AdminDashboardOut(
            logged_in_employee_count=0 if is_limited_staff_view else logged_in_employee_count,
            active_employees=[] if is_limited_staff_view else active_employees,
            prep_time_settings=[] if is_driver_view else self._get_prep_time_settings(),
            oven_load=current_oven_load,
            oven_capacity=self._OVEN_CAPACITY,
            udka_oven_load=current_udka_oven_load,
            udka_oven_capacity=self._UDKA_OVEN_CAPACITY,
            udka_slot_label=self._pickup_slot_dashboard_label(
                now=now,
                slot_datetime=next_udka_slot,
            ),
            pending_order_count=len(pending_orders),
            in_progress_order_count=len(in_progress_orders),
            new_users_this_month=0 if is_limited_staff_view else new_users_this_month,
            completed_orders_today=0 if is_limited_staff_view else completed_orders_today,
            order_history_count=order_history_count,
            turnover_last_days=turnover_last_days,
            pending_orders=pending_orders,
            in_progress_orders=in_progress_orders,
            closed_orders=closed_orders,
            closed_orders_has_more=order_history_count > len(closed_orders),
            my_taken_orders=my_taken_orders,
        )

    def get_prep_time_settings(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
    ) -> list[PrepTimeSettingOut]:
        self._require_admin_user(
            session_token=session_token,
            user_email=user_email,
        )
        return self._get_prep_time_settings()

    def get_admin_staff_presence(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
        query: str | None = None,
    ) -> AdminStaffPresenceOut:
        self._require_admin_role(
            session_token=session_token,
            user_email=user_email,
        )

        now = datetime.utcnow()
        currently_available = self._get_currently_available_staff_presence(now=now)
        current_user_ids = {
            person.user_id for person in currently_available
        }
        recently_available = self._get_recently_available_staff_presence(
            now=now,
            exclude_user_ids=current_user_ids,
        )
        all_results = self._search_staff_presence(
            query=query,
            current_user_ids=current_user_ids,
        )
        return AdminStaffPresenceOut(
            currently_available=currently_available,
            recently_available=recently_available,
            all_results=all_results,
        )

    def get_admin_catalog(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
    ) -> AdminCatalogOut:
        self._require_admin_role(
            session_token=session_token,
            user_email=user_email,
        )

        positions = (
            self.db.query(MenuPositionDB)
            .order_by(
                MenuPositionDB.position_type.asc(),
                MenuPositionDB.name.asc(),
            )
            .all()
        )
        addons = (
            self.db.query(MenuAddonDB)
            .order_by(
                MenuAddonDB.sort_order.asc(),
                MenuAddonDB.name.asc(),
            )
            .all()
        )

        return AdminCatalogOut(
            delivery_minimum_amount=self._get_delivery_minimum_amount(),
            delivery_radius_km=self._get_delivery_radius_km(),
            delivery_origin_address=self._get_delivery_origin_address(),
            positions=[
                AdminCatalogPositionOut(
                    position_id=position.position_id,
                    position_type=position.position_type,
                    name=(position.name or "").strip(),
                    description=position.description,
                    price=float(position.price) if position.price is not None else None,
                    is_active=bool(position.is_active),
                )
                for position in positions
            ],
            addons=[
                AdminCatalogAddonOut(
                    addon_id=addon.addon_id,
                    name=addon.name,
                    description=addon.description,
                    price=float(addon.price),
                    sort_order=addon.sort_order or 0,
                    is_active=bool(addon.is_active),
                )
                for addon in addons
            ],
        )

    def update_admin_catalog_position(
        self,
        position_id: int,
        payload: AdminCatalogItemUpdateIn,
    ) -> AdminCatalogPositionOut:
        self._require_admin_role(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

        position = (
            self.db.query(MenuPositionDB)
            .filter(MenuPositionDB.position_id == position_id)
            .first()
        )
        if position is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono pozycji menu.")

        if payload.is_active is None and payload.price is None:
            raise HTTPException(status_code=400, detail="Brak zmian do zapisania.")

        if payload.is_active is not None:
            position.is_active = bool(payload.is_active)
        if payload.price is not None:
            position.price = self._normalize_catalog_price(payload.price)
        self.db.commit()
        self.db.refresh(position)

        return AdminCatalogPositionOut(
            position_id=position.position_id,
            position_type=position.position_type,
            name=(position.name or "").strip(),
            description=position.description,
            price=float(position.price) if position.price is not None else None,
            is_active=bool(position.is_active),
        )

    def update_admin_catalog_addon(
        self,
        addon_id: int,
        payload: AdminCatalogItemUpdateIn,
    ) -> AdminCatalogAddonOut:
        self._require_admin_role(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

        addon = (
            self.db.query(MenuAddonDB)
            .filter(MenuAddonDB.addon_id == addon_id)
            .first()
        )
        if addon is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono dodatku.")

        if payload.is_active is None and payload.price is None:
            raise HTTPException(status_code=400, detail="Brak zmian do zapisania.")

        if payload.is_active is not None:
            addon.is_active = bool(payload.is_active)
        if payload.price is not None:
            addon.price = self._normalize_catalog_price(payload.price)
        self.db.commit()
        self.db.refresh(addon)

        return AdminCatalogAddonOut(
            addon_id=addon.addon_id,
            name=addon.name,
            description=addon.description,
            price=float(addon.price),
            sort_order=addon.sort_order or 0,
            is_active=bool(addon.is_active),
        )

    def update_delivery_minimum_amount(
        self,
        payload: AdminCatalogDeliveryMinimumUpdateIn,
    ) -> AdminCatalogOut:
        operator = self._require_admin_role(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )
        amount = round(float(payload.amount), 2)
        if amount < 0 or amount > 999:
            raise HTTPException(
                status_code=400,
                detail="Minimalna wartosc dostawy musi miescic sie w zakresie 0-999 PLN.",
            )

        self._set_decimal_runtime_setting(
            setting_key=self._DELIVERY_MINIMUM_SETTING_KEY,
            label="Minimalna wartosc zamowienia z dostawa",
            decimal_value=amount,
            updated_by_user_id=operator.user_id,
        )
        return self.get_admin_catalog(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

    def update_delivery_radius(
        self,
        payload: AdminCatalogDeliveryRadiusUpdateIn,
    ) -> AdminCatalogOut:
        operator = self._require_admin_role(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )
        radius_km = round(float(payload.radius_km), 2)
        if radius_km < 0.5 or radius_km > 50:
            raise HTTPException(
                status_code=400,
                detail="Promien dostawy musi miescic sie w zakresie 0.5-50 km.",
            )

        self._set_decimal_runtime_setting(
            setting_key=self._DELIVERY_RADIUS_SETTING_KEY,
            label="Promien dostawy",
            decimal_value=radius_km,
            updated_by_user_id=operator.user_id,
        )
        return self.get_admin_catalog(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

    def update_delivery_origin_address(
        self,
        payload: AdminCatalogDeliveryOriginAddressUpdateIn,
    ) -> AdminCatalogOut:
        operator = self._require_admin_role(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )
        normalized_address = " ".join((payload.address or "").strip().split())
        if not normalized_address:
            raise HTTPException(
                status_code=400,
                detail="Adres lokalu dla dostaw nie moze byc pusty.",
            )

        geocoded_origin = self._geocode_address(normalized_address)
        if geocoded_origin is None:
            raise HTTPException(
                status_code=409,
                detail="Nie udalo sie potwierdzic adresu lokalu. Sprawdz wpis i sprobuj ponownie.",
            )

        self._set_string_runtime_setting(
            setting_key=self._DELIVERY_ORIGIN_ADDRESS_SETTING_KEY,
            label="Adres lokalu dla dostaw",
            string_value=geocoded_origin["display_name"],
            updated_by_user_id=operator.user_id,
        )
        return self.get_admin_catalog(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

    def validate_delivery_address(
        self,
        payload: DeliveryAddressValidationIn,
    ) -> DeliveryAddressValidationOut:
        origin_address = self._get_delivery_origin_address()
        if not origin_address:
            raise HTTPException(
                status_code=409,
                detail="Adres lokalu dla dostaw nie jest jeszcze ustawiony w panelu administratora.",
            )

        normalized_query = self._normalize_delivery_address_query(
            street=payload.street,
            postal=payload.postal,
            city=payload.city,
        )
        if not normalized_query:
            raise HTTPException(
                status_code=400,
                detail="Podaj ulice, kod pocztowy i miasto.",
            )

        client_geocode = self._geocode_address(normalized_query)
        if client_geocode is None:
            raise HTTPException(
                status_code=409,
                detail="Nie udalo sie potwierdzic adresu dostawy. Sprawdz ulice, kod i miasto.",
            )

        origin_geocode = self._geocode_address(origin_address)
        if origin_geocode is None:
            raise HTTPException(
                status_code=409,
                detail="Nie udalo sie potwierdzic adresu lokalu dla dostaw. Popraw go w panelu administratora.",
            )

        distance_km = self._haversine_distance_km(
            lat1=origin_geocode["lat"],
            lon1=origin_geocode["lon"],
            lat2=client_geocode["lat"],
            lon2=client_geocode["lon"],
        )
        radius_km = self._get_delivery_radius_km()
        if distance_km > radius_km:
            raise HTTPException(
                status_code=409,
                detail=f"Adres jest poza strefa dostawy ({radius_km:.1f} km).",
            )

        return DeliveryAddressValidationOut(
            is_within_radius=True,
            distance_km=distance_km,
            radius_km=radius_km,
            normalized_address=client_geocode["display_name"],
        )

    def update_prep_time_setting(
        self,
        group_key: str,
        payload: PrepTimeSettingUpdateIn,
    ) -> PrepTimeSettingOut:
        operator = self._require_admin_user(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

        normalized_group_key = (group_key or "").strip().lower()
        if not normalized_group_key:
            raise HTTPException(status_code=400, detail="Brak klucza grupy czasu przygotowania.")

        minutes = int(payload.minutes)
        if minutes < 1 or minutes > 180:
            raise HTTPException(
                status_code=400,
                detail="Czas przygotowania musi miescic sie w zakresie 1-180 minut.",
            )

        setting = (
            self.db.query(ProductPrepTimeSettingDB)
            .filter(func.lower(ProductPrepTimeSettingDB.group_key) == normalized_group_key)
            .first()
        )

        if setting is None:
            max_sort_order = self.db.query(func.max(ProductPrepTimeSettingDB.sort_order)).scalar()
            setting = ProductPrepTimeSettingDB(
                group_key=normalized_group_key,
                label=normalized_group_key.replace("_", " ").title(),
                sort_order=(max_sort_order or 0) + 10,
            )
            self.db.add(setting)

        setting.label = setting.label or normalized_group_key.replace("_", " ").title()
        setting.minutes = minutes
        setting.is_active = True
        setting.updated_by_user_id = operator.user_id
        setting.updated_at = datetime.utcnow()

        self.db.commit()
        self.db.refresh(setting)
        return self._serialize_prep_time_setting(setting)

    def update_admin_order_status(
        self,
        checkout_order_id: int,
        payload: AdminOrderStatusUpdateIn,
    ) -> AdminDashboardOrderOut:
        operator = self._require_admin_user(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )
        normalized_role = (operator.role or "").strip().lower()

        processing_status = self._normalize_processing_status(payload.processing_status)
        verification_stage = self._normalize_operator_verification_stage(
            processing_status=processing_status,
            verification_stage=payload.verification_stage,
        )
        checkout_order = (
            self.db.query(CheckoutOrderDB)
            .options(
                joinedload(CheckoutOrderDB.items),
                joinedload(CheckoutOrderDB.chat_messages),
            )
            .filter(CheckoutOrderDB.checkout_order_id == checkout_order_id)
            .first()
        )
        if checkout_order is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono zamowienia checkout.")

        if normalized_role == DRIVER_ROLE and not self._is_driver_order(checkout_order):
            raise HTTPException(
                status_code=403,
                detail="Kierowca moze obslugiwac tylko zamowienia z dostawa.",
            )

        supports_progress_updates = self._order_supports_progress_updates(checkout_order)

        if (
            checkout_order.processing_status == CHECKOUT_ORDER_STATUS_COMPLETED
            and processing_status != CHECKOUT_ORDER_STATUS_COMPLETED
        ):
            raise HTTPException(
                status_code=409,
                detail="Zamowienie zostalo juz zakonczone i nie moze wrocic na tablice admina.",
            )

        if (
            not supports_progress_updates
            and verification_stage == "in_oven"
        ):
            raise HTTPException(
                status_code=409,
                detail="To zamowienie nie obsluguje etapu pieca.",
            )

        is_delivery_order = self._is_driver_order(checkout_order)
        is_ready_for_delivery_transition = verification_stage == "ready_for_delivery"

        if normalized_role == DRIVER_ROLE and verification_stage == "in_oven":
            raise HTTPException(
                status_code=403,
                detail="Kierowca nie moze oznaczac etapu pieca.",
            )

        if verification_stage == "in_oven":
            oven_kind = self._order_oven_kind(checkout_order)
            if oven_kind == "udka":
                slot_datetime = self._scheduled_pickup_at_for_order(checkout_order)
                oven_load_without_current = (
                    self._get_udka_slot_load(
                        slot_datetime,
                        exclude_checkout_order_id=checkout_order.checkout_order_id,
                    )
                    if slot_datetime is not None
                    else 0
                )
            else:
                oven_load_without_current = self._get_current_oven_load(
                    exclude_checkout_order_id=checkout_order.checkout_order_id,
                )
            order_oven_slot_count = self._order_oven_slot_count(checkout_order)
            oven_capacity = self._oven_capacity_for_kind(oven_kind)
            if (
                order_oven_slot_count <= 0
                or oven_load_without_current + order_oven_slot_count > oven_capacity
            ):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Piec jest obecnie pelny. Zwolnij miejsce w piecu i sprobuj ponownie."
                    ),
                )

        if is_ready_for_delivery_transition:
            if normalized_role == DRIVER_ROLE:
                raise HTTPException(
                    status_code=403,
                    detail="Kierowca nie moze oznaczac zamowienia jako gotowego do wysylki.",
                )
            if not is_delivery_order:
                raise HTTPException(
                    status_code=409,
                    detail="Etap gotowosci do wysylki dotyczy tylko zamowien z dostawa.",
                )
        elif (
            verification_stage == "on_the_way"
            and is_delivery_order
            and normalized_role != DRIVER_ROLE
        ):
            raise HTTPException(
                status_code=403,
                detail="Status w dostawie jest ustawiany dopiero po podjeciu zamowienia przez kierowce.",
            )

        checkout_order.processing_status = processing_status
        if processing_status == CHECKOUT_ORDER_STATUS_ASSIGNED:
            if (
                normalized_role == DRIVER_ROLE
                and checkout_order.assigned_to_user_id is None
                and not self._is_ready_for_delivery_stage(checkout_order)
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Kierowca moze podjac tylko dostawe oznaczona jako gotowa do wysylki.",
                )
            if (
                normalized_role != DRIVER_ROLE
                and is_delivery_order
                and self._is_ready_for_delivery_stage(checkout_order)
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Dostawe gotowa do wysylki moze podjac tylko kierowca.",
                )
            if (
                checkout_order.assigned_to_user_id is not None
                and checkout_order.assigned_to_user_id != operator.user_id
            ):
                raise HTTPException(
                    status_code=409,
                    detail="To zamowienie zostalo juz podjete przez innego operatora.",
                )
            if checkout_order.assigned_to_user_id is None:
                checkout_order.assigned_to_user_id = operator.user_id
            if checkout_order.assigned_at is None:
                checkout_order.assigned_at = datetime.utcnow()
            if is_ready_for_delivery_transition:
                checkout_order.processing_status = CHECKOUT_ORDER_STATUS_UNASSIGNED
                checkout_order.assigned_to_user_id = None
                checkout_order.assigned_at = None
                checkout_order.verification_stage = "ready_for_delivery"
            elif (
                normalized_role == DRIVER_ROLE
                and self._is_ready_for_delivery_stage(checkout_order)
                and not verification_stage
            ):
                checkout_order.verification_stage = "on_the_way"
            else:
                checkout_order.verification_stage = verification_stage or "assigned"
        elif processing_status == CHECKOUT_ORDER_STATUS_UNASSIGNED:
            if (
                normalized_role == DRIVER_ROLE
                and checkout_order.assigned_to_user_id is not None
                and checkout_order.assigned_to_user_id != operator.user_id
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Kierowca nie moze cofnac dostawy przypisanej do innej osoby.",
                )
            checkout_order.assigned_to_user_id = None
            checkout_order.assigned_at = None
            checkout_order.verification_stage = (
                "ready_for_delivery"
                if is_delivery_order and self._is_ready_for_delivery_stage(checkout_order)
                else "accepted"
            )
        if processing_status == CHECKOUT_ORDER_STATUS_COMPLETED:
            if (
                normalized_role == DRIVER_ROLE
                and checkout_order.assigned_to_user_id is not None
                and checkout_order.assigned_to_user_id != operator.user_id
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Kierowca moze zakonczyc tylko dostawe przypisana do siebie.",
                )
            now = datetime.utcnow()
            if normalized_role == DRIVER_ROLE and is_delivery_order:
                checkout_order.status = "awaiting_receipt_confirmation"
                checkout_order.processing_status = CHECKOUT_ORDER_STATUS_COMPLETED
                checkout_order.verification_stage = "awaiting_receipt_confirmation"
                checkout_order.active_until = now
                if checkout_order.receipt_confirmation_requested_at is None:
                    checkout_order.receipt_confirmation_requested_at = now
            else:
                checkout_order.status = "completed"
                checkout_order.verification_stage = "completed_by_admin"
                checkout_order.active_until = now
                if checkout_order.receipt_confirmed_at is None:
                    checkout_order.receipt_confirmed_at = now

        self.db.commit()
        self.db.refresh(checkout_order)

        customer_email = None
        if checkout_order.user_id is not None:
            customer = self.db.query(UserDB).filter(UserDB.user_id == checkout_order.user_id).first()
            customer_email = customer.email if customer is not None else None
        current_oven_load = self._get_current_oven_load()
        current_udka_oven_load = self._get_udka_slot_load(
            self._next_pickup_slot_datetime(now=datetime.utcnow()),
        )

        return self._build_admin_order(
            checkout_order,
            customer_email=customer_email,
            now=datetime.utcnow(),
            current_user_id=operator.user_id,
            assigned_operator_email=operator.email
            if checkout_order.assigned_to_user_id == operator.user_id
            else None,
            current_oven_load=current_oven_load,
            current_udka_oven_load=current_udka_oven_load,
        )

    def get_active_checkout(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
    ) -> CheckoutVerificationOut | None:
        user_id = self._resolve_user_id(
            session_token=session_token,
            user_email=user_email,
        )

        if user_id is None:
            return None

        now = datetime.utcnow()
        self._refresh_checkout_states(user_id=user_id, now=now)
        checkout_order = self._get_current_checkout_order(user_id=user_id, now=now)

        if checkout_order is None:
            return None

        return self._build_response(checkout_order, now)

    def get_checkout_history(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
        page: int = 1,
        page_size: int = _CHECKOUT_HISTORY_DEFAULT_PAGE_SIZE,
    ) -> CheckoutHistoryPageOut:
        user_id = self._resolve_user_id(
            session_token=session_token,
            user_email=user_email,
        )
        if user_id is None:
            return CheckoutHistoryPageOut(orders=[])

        now = datetime.utcnow()
        self._refresh_checkout_states(user_id=user_id, now=now)
        normalized_page, normalized_page_size, offset = self._normalize_pagination(
            page=page,
            page_size=page_size,
            default_page_size=self._CHECKOUT_HISTORY_DEFAULT_PAGE_SIZE,
            max_page_size=self._CHECKOUT_HISTORY_MAX_PAGE_SIZE,
        )
        base_query = (
            self.db.query(CheckoutOrderDB)
            .options(joinedload(CheckoutOrderDB.items))
            .filter(
                CheckoutOrderDB.user_id == user_id,
                or_(
                    CheckoutOrderDB.status == "completed",
                    CheckoutOrderDB.processing_status == CHECKOUT_ORDER_STATUS_COMPLETED,
                ),
            )
        )
        total_count = base_query.count()
        checkout_orders = (
            base_query
            .order_by(self._closed_orders_sort_expression().desc())
            .offset(offset)
            .limit(normalized_page_size)
            .all()
        )
        orders = [
            self._build_response(checkout_order, now=now)
            for checkout_order in checkout_orders
        ]
        return CheckoutHistoryPageOut(
            page=normalized_page,
            page_size=normalized_page_size,
            total_count=total_count,
            has_more=(offset + len(orders)) < total_count,
            orders=orders,
        )

    def get_admin_closed_orders_history(
        self,
        session_token: str | None = None,
        user_email: str | None = None,
        page: int = 1,
        page_size: int = _ADMIN_HISTORY_DEFAULT_PAGE_SIZE,
        today_only: bool = False,
    ) -> AdminClosedOrdersPageOut:
        current_user = self._require_admin_user(
            session_token=session_token,
            user_email=user_email,
        )
        now = datetime.utcnow()
        normalized_role = (current_user.role or "").strip().lower()
        normalized_page, normalized_page_size, offset = self._normalize_pagination(
            page=page,
            page_size=page_size,
            default_page_size=self._ADMIN_HISTORY_DEFAULT_PAGE_SIZE,
            max_page_size=self._ADMIN_HISTORY_MAX_PAGE_SIZE,
        )

        base_query = self._closed_orders_query(
            current_user=current_user,
            normalized_role=normalized_role,
            today_only=today_only,
        )
        total_count = base_query.count()
        closed_rows = (
            base_query
            .outerjoin(UserDB, UserDB.user_id == CheckoutOrderDB.user_id)
            .options(
                joinedload(CheckoutOrderDB.items),
                joinedload(CheckoutOrderDB.chat_messages),
            )
            .order_by(self._closed_orders_sort_expression().desc())
            .offset(offset)
            .limit(normalized_page_size)
            .all()
        )
        assigned_user_ids = {
            checkout_order.assigned_to_user_id
            for checkout_order in closed_rows
            if checkout_order.assigned_to_user_id is not None
        }
        assigned_user_emails = {
            user.user_id: user.email
            for user in self.db.query(UserDB).filter(UserDB.user_id.in_(assigned_user_ids)).all()
        } if assigned_user_ids else {}

        orders = [
            self._build_admin_order(
                checkout_order,
                customer_email=None,
                now=now,
                current_user_id=current_user.user_id,
                assigned_operator_email=assigned_user_emails.get(
                    checkout_order.assigned_to_user_id,
                ),
                current_oven_load=0,
            )
            for checkout_order in closed_rows
        ]
        return AdminClosedOrdersPageOut(
            page=normalized_page,
            page_size=normalized_page_size,
            total_count=total_count,
            has_more=(offset + len(orders)) < total_count,
            orders=orders,
        )

    def confirm_receipt(
        self,
        payload: CheckoutReceiptConfirmationIn,
    ) -> CheckoutVerificationOut:
        user_id = self._resolve_user_id(
            session_token=payload.session_token,
            user_email=payload.user_email,
        )

        if user_id is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono uzytkownika checkout.")

        now = datetime.utcnow()
        self._refresh_checkout_states(user_id=user_id, now=now)
        checkout_order = self._get_current_checkout_order(user_id=user_id, now=now)

        if checkout_order is None:
            raise HTTPException(status_code=404, detail="Brak aktywnego zamowienia do potwierdzenia.")

        if payload.received:
            checkout_order.status = "completed"
            checkout_order.processing_status = CHECKOUT_ORDER_STATUS_COMPLETED
            checkout_order.verification_stage = "delivered_confirmed"
            checkout_order.receipt_confirmed_at = now
            checkout_order.active_until = now
            self.db.commit()
            self.db.refresh(checkout_order)
            return self._build_response(
                checkout_order,
                now=now,
                message="Dziekujemy za potwierdzenie odbioru zamowienia.",
            )

        checkout_order.status = "active"
        checkout_order.verification_stage = "delivery_extended"
        checkout_order.active_until = now + timedelta(minutes=10)
        checkout_order.receipt_confirmation_requested_at = None
        checkout_order.delivery_extension_count = (
            (checkout_order.delivery_extension_count or 0) + 1
        )
        checkout_order.support_alert_sent_at = now

        support_message = (
            f"Uzytkownik {user_id} nie potwierdzil odbioru zamowienia "
            f"{checkout_order.checkout_order_id}. Wydluzono ETA o 10 minut."
        )
        self.db.add(
            CheckoutSupportAlertDB(
                checkout_order_id=checkout_order.checkout_order_id,
                user_id=user_id,
                message=support_message,
                created_at=now,
            )
        )
        self.db.commit()
        self.db.refresh(checkout_order)
        return self._build_response(
            checkout_order,
            now=now,
            message="Dodano dodatkowe 10 minut oczekiwania i przekazano zgloszenie do obslugi.",
        )

    def get_order_messages(
        self,
        checkout_order_id: int,
        session_token: str | None = None,
        user_email: str | None = None,
    ) -> list[CheckoutOrderMessageOut]:
        checkout_order, _, _ = self._require_checkout_order_access(
            checkout_order_id=checkout_order_id,
            session_token=session_token,
            user_email=user_email,
            allow_staff=True,
        )

        messages = (
            self.db.query(CheckoutOrderMessageDB)
            .filter(CheckoutOrderMessageDB.checkout_order_id == checkout_order.checkout_order_id)
            .order_by(
                CheckoutOrderMessageDB.created_at.asc(),
                CheckoutOrderMessageDB.checkout_order_message_id.asc(),
            )
            .all()
        )
        return [self._serialize_checkout_message(message) for message in messages]

    def create_order_message(
        self,
        checkout_order_id: int,
        payload: CheckoutOrderMessageCreateIn,
    ) -> CheckoutOrderMessageOut:
        checkout_order, current_user, normalized_role = self._require_checkout_order_access(
            checkout_order_id=checkout_order_id,
            session_token=payload.session_token,
            user_email=payload.user_email,
            allow_staff=True,
        )

        text = (payload.message or "").strip()
        if not text:
            raise HTTPException(status_code=400, detail="Wiadomosc nie moze byc pusta.")

        if len(text) > 600:
            raise HTTPException(
                status_code=400,
                detail="Wiadomosc nie moze przekraczac 600 znakow.",
            )

        sender_role = self._chat_sender_role_for_user(normalized_role)
        if sender_role == "staff":
            self._ensure_staff_can_access_order_messages(
                checkout_order=checkout_order,
                current_user=current_user,
                normalized_role=normalized_role,
            )

        chat_message = CheckoutOrderMessageDB(
            checkout_order_id=checkout_order.checkout_order_id,
            sender_user_id=current_user.user_id,
            sender_role=sender_role,
            author_label=self._chat_author_label(current_user, sender_role),
            message=text,
            created_at=datetime.utcnow(),
            staff_read_at=datetime.utcnow() if sender_role == "staff" else None,
        )

        self.db.add(chat_message)
        self.db.commit()
        self.db.refresh(chat_message)
        return self._serialize_checkout_message(chat_message)

    def mark_order_messages_read(
        self,
        checkout_order_id: int,
        payload: CheckoutOrderMessagesReadIn,
    ) -> CheckoutOrderMessagesReadOut:
        checkout_order, current_user, normalized_role = self._require_checkout_order_access(
            checkout_order_id=checkout_order_id,
            session_token=payload.session_token,
            user_email=payload.user_email,
            allow_staff=True,
        )
        self._ensure_staff_can_access_order_messages(
            checkout_order=checkout_order,
            current_user=current_user,
            normalized_role=normalized_role,
        )

        now = datetime.utcnow()
        messages = (
            self.db.query(CheckoutOrderMessageDB)
            .filter(
                CheckoutOrderMessageDB.checkout_order_id == checkout_order.checkout_order_id,
                func.lower(CheckoutOrderMessageDB.sender_role) == "customer",
                CheckoutOrderMessageDB.staff_read_at.is_(None),
            )
            .all()
        )

        for message in messages:
            message.staff_read_at = now

        self.db.commit()
        return CheckoutOrderMessagesReadOut(updated_count=len(messages))

    def _refresh_checkout_states(self, user_id: int, now: datetime) -> None:
        stale_orders = (
            self.db.query(CheckoutOrderDB)
            .filter(
                CheckoutOrderDB.user_id == user_id,
                CheckoutOrderDB.status == "active",
                CheckoutOrderDB.active_until <= now,
            )
            .all()
        )

        if not stale_orders:
            return

        for order in stale_orders:
            order.status = "awaiting_receipt_confirmation"
            order.verification_stage = "awaiting_receipt_confirmation"
            if order.receipt_confirmation_requested_at is None:
                order.receipt_confirmation_requested_at = now

        self.db.commit()

    def _get_current_checkout_order(
        self,
        user_id: int,
        now: datetime,
    ) -> CheckoutOrderDB | None:
        return (
            self.db.query(CheckoutOrderDB)
            .filter(
                CheckoutOrderDB.user_id == user_id,
                or_(
                    (CheckoutOrderDB.status == "active") & (CheckoutOrderDB.active_until > now),
                    CheckoutOrderDB.status == "awaiting_receipt_confirmation",
                ),
            )
            .order_by(CheckoutOrderDB.created_at.desc())
            .first()
        )

    def _build_response(
        self,
        checkout_order: CheckoutOrderDB,
        now: datetime | None = None,
        message: str | None = None,
    ) -> CheckoutVerificationOut:
        reference_time = now or datetime.utcnow()
        requires_receipt_confirmation = (
            checkout_order.verification_stage == "awaiting_receipt_confirmation"
        )
        remaining_eta_minutes = self._remaining_eta_minutes(
            checkout_order=checkout_order,
            now=reference_time,
            include_oven_queue=not requires_receipt_confirmation,
        )

        payload = CheckoutVerificationIn(
            created_at=self._as_utc(checkout_order.client_created_at),
            currency=checkout_order.currency,
            total_amount=float(checkout_order.total_amount),
            eta_minutes=checkout_order.eta_minutes,
            payment_method=checkout_order.payment_method,
            fulfillment_method=checkout_order.fulfillment_method,
            fulfillment_option_index=checkout_order.fulfillment_option_index,
            address_option_index=checkout_order.address_option_index,
            address=CheckoutAddressPayload(
                title=checkout_order.address_title,
                subtitle=checkout_order.address_subtitle,
                eta_label=checkout_order.address_eta_label,
            ),
            items=[
                CheckoutItemPayload(
                    cart_entry_id=item.cart_entry_id,
                    position_id=item.position_id,
                    name=item.name,
                    description=item.description,
                    photo_url=item.photo_url,
                    calories=item.calories,
                    price=float(item.price) if item.price is not None else None,
                )
                for item in checkout_order.items
            ],
            subtotal_amount=float(checkout_order.subtotal_amount),
            redeemed_points=checkout_order.redeemed_points or 0,
            redeemed_amount=float(checkout_order.redeemed_amount or 0),
            notes=checkout_order.notes,
            session_token=None,
            user_email=None,
        )

        return CheckoutVerificationOut(
            verification_id=checkout_order.verification_id,
            saved_order_id=checkout_order.checkout_order_id,
            status=checkout_order.status,
            processing_status=checkout_order.processing_status,
            payment_method=checkout_order.payment_method,
            verification_stage=checkout_order.verification_stage,
            message=message or (
                "Czy otrzymales juz swoje zamowienie?"
                if requires_receipt_confirmation
                else "Aktywne zamowienie oczekuje na kolejne etapy realizacji."
            ),
            created_at=self._as_utc(checkout_order.created_at),
            active_until=self._as_utc(checkout_order.active_until),
            remaining_eta_minutes=remaining_eta_minutes,
            requires_receipt_confirmation=requires_receipt_confirmation,
            receipt_confirmation_requested_at=self._as_utc(
                checkout_order.receipt_confirmation_requested_at,
            ),
            support_alert_sent_at=self._as_utc(checkout_order.support_alert_sent_at),
            delivery_extension_count=checkout_order.delivery_extension_count or 0,
            awarded_points=loyalty_points_for_order_total(
                float(checkout_order.subtotal_amount),
            ),
            user_points_balance=self._get_user_loyalty_points(checkout_order.user_id),
            scheduled_pickup_at=self._scheduled_pickup_at_for_order(checkout_order),
            received_order=payload,
        )

    def _calculate_checkout_subtotal_amount(
        self,
        items: list[CheckoutItemPayload],
    ) -> float:
        subtotal_amount = round(
            sum(float(item.price or 0) for item in items),
            2,
        )
        return max(0.0, subtotal_amount)

    def _resolve_redeemed_points(
        self,
        user: UserDB | None,
        requested_points: int | None,
        subtotal_amount: float,
    ) -> tuple[int, float]:
        if user is None:
            return 0, 0.0

        normalized_requested_points = max(0, int(requested_points or 0))
        if normalized_requested_points <= 0 or subtotal_amount <= 0:
            return 0, 0.0

        max_points_for_order = int(subtotal_amount * 0.3) * LOYALTY_POINTS_PER_1_PLN
        available_points = int(user.loyalty_points or 0)
        applied_points = min(
            normalized_requested_points,
            max_points_for_order,
            available_points,
        )
        applied_points -= applied_points % LOYALTY_POINTS_PER_1_PLN
        if applied_points <= 0:
            return 0, 0.0

        redeemed_amount = round(applied_points / LOYALTY_POINTS_PER_1_PLN, 2)
        return applied_points, redeemed_amount

    def _get_user_loyalty_points(self, user_id: int | None) -> int:
        if user_id is None:
            return 0

        user = self.db.query(UserDB).filter(UserDB.user_id == user_id).first()
        return int(user.loyalty_points or 0) if user is not None else 0

    def _get_prep_time_settings_rows(self) -> list[ProductPrepTimeSettingDB]:
        return (
            self.db.query(ProductPrepTimeSettingDB)
            .filter(ProductPrepTimeSettingDB.is_active == True)
            .order_by(
                ProductPrepTimeSettingDB.sort_order.asc(),
                ProductPrepTimeSettingDB.label.asc(),
            )
            .all()
        )

    def _get_prep_time_settings(self) -> list[PrepTimeSettingOut]:
        return [
            self._serialize_prep_time_setting(setting)
            for setting in self._get_prep_time_settings_rows()
        ]

    def _serialize_prep_time_setting(
        self,
        setting: ProductPrepTimeSettingDB,
    ) -> PrepTimeSettingOut:
        return PrepTimeSettingOut(
            group_key=setting.group_key,
            label=setting.label,
            minutes=setting.minutes,
            sort_order=setting.sort_order or 0,
            is_active=bool(setting.is_active),
        )

    def _get_delivery_minimum_amount(self) -> float:
        return self._get_decimal_runtime_setting(
            setting_key=self._DELIVERY_MINIMUM_SETTING_KEY,
            default_value=self._DEFAULT_DELIVERY_MINIMUM_AMOUNT,
        )

    def _get_delivery_radius_km(self) -> float:
        return self._get_decimal_runtime_setting(
            setting_key=self._DELIVERY_RADIUS_SETTING_KEY,
            default_value=self._DEFAULT_DELIVERY_RADIUS_KM,
        )

    def _get_delivery_origin_address(self) -> str:
        return self._get_string_runtime_setting(
            setting_key=self._DELIVERY_ORIGIN_ADDRESS_SETTING_KEY,
            default_value="",
        )

    def _get_decimal_runtime_setting(
        self,
        setting_key: str,
        default_value: float,
    ) -> float:
        setting = (
            self.db.query(AppRuntimeSettingDB)
            .filter(AppRuntimeSettingDB.setting_key == setting_key)
            .first()
        )
        if setting is None or setting.decimal_value is None:
            return round(float(default_value), 2)
        return round(float(setting.decimal_value), 2)

    def _set_decimal_runtime_setting(
        self,
        setting_key: str,
        label: str,
        decimal_value: float,
        updated_by_user_id: int | None,
    ) -> None:
        setting = (
            self.db.query(AppRuntimeSettingDB)
            .filter(AppRuntimeSettingDB.setting_key == setting_key)
            .first()
        )
        if setting is None:
            setting = AppRuntimeSettingDB(
                setting_key=setting_key,
                label=label,
            )
            self.db.add(setting)

        setting.label = label
        setting.decimal_value = round(float(decimal_value), 2)
        setting.updated_by_user_id = updated_by_user_id
        setting.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(setting)

    def _get_string_runtime_setting(
        self,
        setting_key: str,
        default_value: str,
    ) -> str:
        setting = (
            self.db.query(AppRuntimeSettingDB)
            .filter(AppRuntimeSettingDB.setting_key == setting_key)
            .first()
        )
        if setting is None or setting.string_value is None:
            return default_value
        return str(setting.string_value).strip()

    def _set_string_runtime_setting(
        self,
        setting_key: str,
        label: str,
        string_value: str,
        updated_by_user_id: int | None,
    ) -> None:
        setting = (
            self.db.query(AppRuntimeSettingDB)
            .filter(AppRuntimeSettingDB.setting_key == setting_key)
            .first()
        )
        if setting is None:
            setting = AppRuntimeSettingDB(
                setting_key=setting_key,
                label=label,
            )
            self.db.add(setting)

        setting.label = label
        setting.string_value = string_value.strip()
        setting.updated_by_user_id = updated_by_user_id
        setting.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(setting)

    def _normalize_delivery_address_query(
        self,
        street: str,
        postal: str,
        city: str,
    ) -> str:
        parts = [
            " ".join((street or "").strip().split()),
            " ".join((postal or "").strip().split()),
            " ".join((city or "").strip().split()),
        ]
        return ", ".join(part for part in parts if part)

    def _geocode_address(self, query: str) -> dict[str, float | str] | None:
        normalized_query = " ".join((query or "").strip().split())
        if not normalized_query:
            return None

        url = (
            f"{self._NOMINATIM_SEARCH_URL}?q={quote_plus(normalized_query)}"
            "&format=jsonv2&limit=1&countrycodes=pl"
        )
        request = Request(
            url,
            headers={
                "User-Agent": self._NOMINATIM_USER_AGENT,
                "Accept": "application/json",
            },
        )

        try:
            with urlopen(request, timeout=8) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            raise HTTPException(
                status_code=502,
                detail="Nie udalo sie polaczyc z usluga weryfikacji adresow.",
            ) from exc

        if not isinstance(payload, list) or not payload:
            return None

        top_result = payload[0]
        try:
            lat = float(top_result["lat"])
            lon = float(top_result["lon"])
            display_name = str(top_result["display_name"]).strip()
        except (KeyError, TypeError, ValueError):
            return None

        return {
            "lat": lat,
            "lon": lon,
            "display_name": display_name,
        }

    def _haversine_distance_km(
        self,
        *,
        lat1: float,
        lon1: float,
        lat2: float,
        lon2: float,
    ) -> float:
        earth_radius_km = 6371.0
        lat1_rad = math.radians(lat1)
        lon1_rad = math.radians(lon1)
        lat2_rad = math.radians(lat2)
        lon2_rad = math.radians(lon2)
        delta_lat = lat2_rad - lat1_rad
        delta_lon = lon2_rad - lon1_rad

        a = (
            math.sin(delta_lat / 2) ** 2
            + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon / 2) ** 2
        )
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return round(earth_radius_km * c, 2)

    def _normalize_catalog_price(self, price: float) -> float:
        normalized_price = round(float(price), 2)
        if normalized_price < 0 or normalized_price > 999:
            raise HTTPException(
                status_code=400,
                detail="Cena musi miescic sie w zakresie 0-999 PLN.",
            )
        return normalized_price

    def _calculate_checkout_eta_minutes(
        self,
        items: list[CheckoutItemPayload],
        fallback_minutes: int,
        fulfillment_method: str,
        fulfillment_option_index: int,
        now: datetime,
        positions: list[MenuPositionDB] | None = None,
        pickup_slot_datetime: datetime | None = None,
    ) -> int:
        if self._is_delivery_fulfillment(
            fulfillment_method,
            fulfillment_option_index,
        ):
            return (
                self._BUSY_DELIVERY_ETA_MINUTES
                if self._has_delivery_in_progress(now)
                else self._STANDARD_DELIVERY_ETA_MINUTES
            )

        safe_fallback = max(1, int(fallback_minutes or 0))
        resolved_positions = positions or self._resolve_checkout_positions(items)
        if not resolved_positions:
            return safe_fallback

        if self._is_pickup_slot_order(
            positions=resolved_positions,
            fulfillment_method=fulfillment_method,
            fulfillment_option_index=fulfillment_option_index,
        ):
            return self._pickup_slot_eta_minutes(
                now=now,
                slot_datetime=pickup_slot_datetime
                or self._resolve_pickup_slot_datetime(
                    now=now,
                    positions=resolved_positions,
                ),
            )

        prep_settings_by_group = {
            setting.group_key: setting
            for setting in self._get_prep_time_settings_rows()
        }
        prep_minutes: list[int] = []
        for position in resolved_positions:
            group_key = infer_prep_group_key(position.position_type, position.name)
            if not group_key:
                continue
            setting = prep_settings_by_group.get(group_key)
            if setting is None or not setting.is_active:
                continue
            if setting.minutes > 0:
                prep_minutes.append(setting.minutes)

        if not prep_minutes:
            return safe_fallback

        return max(prep_minutes)

    def _is_delivery_fulfillment(
        self,
        fulfillment_method: str | None,
        fulfillment_option_index: int | None,
    ) -> bool:
        normalized_method = (fulfillment_method or "").strip().lower()
        return fulfillment_option_index == 0 or normalized_method in {"dostawa", "delivery"}

    def _is_planned_pickup_fulfillment(
        self,
        fulfillment_method: str | None,
        fulfillment_option_index: int | None,
    ) -> bool:
        normalized_method = (fulfillment_method or "").strip().lower()
        return fulfillment_option_index == 2 or normalized_method in {
            "zaplanuj odbior",
            "scheduled pickup",
        }

    def _is_driver_order(self, checkout_order: CheckoutOrderDB) -> bool:
        return self._is_delivery_fulfillment(
            checkout_order.fulfillment_method,
            checkout_order.fulfillment_option_index,
        )

    def _is_ready_for_delivery_stage(self, checkout_order: CheckoutOrderDB) -> bool:
        return (checkout_order.verification_stage or "").strip().lower() == "ready_for_delivery"

    def _has_delivery_in_progress(self, now: datetime) -> bool:
        return (
            self.db.query(CheckoutOrderDB.checkout_order_id)
            .filter(
                CheckoutOrderDB.status != "completed",
                CheckoutOrderDB.processing_status != CHECKOUT_ORDER_STATUS_COMPLETED,
                CheckoutOrderDB.verification_stage.in_(
                    self._DELIVERY_IN_PROGRESS_STAGES
                ),
                CheckoutOrderDB.active_until > now,
            )
            .first()
            is not None
        )

    def _delivery_eta_label(self, eta_minutes: int) -> str:
        return f"~{eta_minutes} min."

    def _pickup_slot_eta_label(
        self,
        now: datetime,
        slot_datetime: datetime | None = None,
    ) -> str:
        next_slot = slot_datetime or self._next_pickup_slot_datetime(now=now)
        same_day = self._as_pickup_local_datetime(now=now).date() == next_slot.date()
        if same_day:
            return f"Odbior o {next_slot.strftime('%H:%M')}"
        return f"Odbior {next_slot.strftime('%d.%m %H:%M')}"

    def _pickup_slot_dashboard_label(
        self,
        now: datetime,
        slot_datetime: datetime,
    ) -> str:
        same_day = self._as_pickup_local_datetime(now=now).date() == slot_datetime.date()
        return slot_datetime.strftime('%H:%M' if same_day else '%d.%m %H:%M')

    def _pickup_slot_eta_minutes(
        self,
        now: datetime,
        slot_datetime: datetime | None = None,
    ) -> int:
        now_local = self._as_pickup_local_datetime(now=now)
        next_slot = slot_datetime or self._next_pickup_slot_datetime(now=now)
        delta_seconds = max(0.0, (next_slot - now_local).total_seconds())
        return int((delta_seconds + 59) // 60)

    def _resolve_pickup_slot_datetime(
        self,
        now: datetime,
        positions: list[MenuPositionDB],
    ) -> datetime:
        required_udka_pieces = self._udka_piece_count_for_positions(positions)
        return self._next_pickup_slot_datetime(
            now=now,
            required_udka_pieces=required_udka_pieces,
        )

    def _next_pickup_slot_datetime(
        self,
        now: datetime,
        required_udka_pieces: int = 0,
    ) -> datetime:
        now_local = self._as_pickup_local_datetime(now=now)
        candidate = self._next_pickup_slot_candidate(now_local)
        if required_udka_pieces <= 0:
            return candidate

        max_iterations = 64
        for _ in range(max_iterations):
            slot_load = self._get_udka_slot_load(candidate)
            if slot_load + required_udka_pieces <= self._UDKA_OVEN_CAPACITY:
                return candidate
            candidate = self._advance_pickup_slot_candidate(candidate)

        raise HTTPException(
            status_code=409,
            detail="Nie udalo sie wyznaczyc wolnej transzy dla udek.",
        )

    def _next_pickup_slot_candidate(self, now_local: datetime) -> datetime:
        candidate_date = now_local.date()
        for slot_hour in self._PICKUP_SLOT_HOURS:
            candidate = datetime(
                year=candidate_date.year,
                month=candidate_date.month,
                day=candidate_date.day,
                hour=slot_hour,
                minute=0,
                second=0,
                microsecond=0,
                tzinfo=self._PICKUP_SLOT_TIMEZONE,
            )
            if candidate >= now_local:
                return candidate
        return self._advance_pickup_slot_candidate(
            datetime(
                year=candidate_date.year,
                month=candidate_date.month,
                day=candidate_date.day,
                hour=self._PICKUP_SLOT_HOURS[-1],
                minute=0,
                second=0,
                microsecond=0,
                tzinfo=self._PICKUP_SLOT_TIMEZONE,
            )
        )

    def _advance_pickup_slot_candidate(self, slot_datetime: datetime) -> datetime:
        try:
            current_index = self._PICKUP_SLOT_HOURS.index(slot_datetime.hour)
        except ValueError:
            current_index = len(self._PICKUP_SLOT_HOURS) - 1

        if current_index < len(self._PICKUP_SLOT_HOURS) - 1:
            next_hour = self._PICKUP_SLOT_HOURS[current_index + 1]
            return slot_datetime.replace(
                hour=next_hour,
                minute=0,
                second=0,
                microsecond=0,
            )

        next_day = slot_datetime.date() + timedelta(days=1)
        return datetime(
            year=next_day.year,
            month=next_day.month,
            day=next_day.day,
            hour=self._PICKUP_SLOT_HOURS[0],
            minute=0,
            second=0,
            microsecond=0,
            tzinfo=self._PICKUP_SLOT_TIMEZONE,
        )

    def _as_pickup_local_datetime(self, now: datetime) -> datetime:
        if now.tzinfo is None:
            now = now.replace(tzinfo=timezone.utc)
        else:
            now = now.astimezone(timezone.utc)
        return now.astimezone(self._PICKUP_SLOT_TIMEZONE)

    def _pickup_slot_datetime_from_label(
        self,
        eta_label: str | None,
        reference_datetime: datetime,
    ) -> datetime | None:
        normalized = (eta_label or "").strip()
        if not normalized:
            return None

        local_reference = self._as_pickup_local_datetime(reference_datetime)
        parts = normalized.split()
        if len(parts) >= 2 and "." in parts[-2] and ":" in parts[-1]:
            try:
                day, month = [int(value) for value in parts[-2].split(".")]
                hour, minute = [int(value) for value in parts[-1].split(":")]
                return datetime(
                    year=local_reference.year,
                    month=month,
                    day=day,
                    hour=hour,
                    minute=minute,
                    second=0,
                    microsecond=0,
                    tzinfo=self._PICKUP_SLOT_TIMEZONE,
                )
            except ValueError:
                return None

        if ":" in normalized:
            time_token = normalized.split()[-1]
            try:
                hour, minute = [int(value) for value in time_token.split(":")]
                return datetime(
                    year=local_reference.year,
                    month=local_reference.month,
                    day=local_reference.day,
                    hour=hour,
                    minute=minute,
                    second=0,
                    microsecond=0,
                    tzinfo=self._PICKUP_SLOT_TIMEZONE,
                )
            except ValueError:
                return None

        return None

    def _scheduled_pickup_at_for_order(
        self,
        checkout_order: CheckoutOrderDB,
    ) -> datetime | None:
        if self._order_oven_kind(checkout_order) != "udka":
            return None
        parsed_slot = self._pickup_slot_datetime_from_label(
            checkout_order.address_eta_label,
            checkout_order.created_at,
        )
        if parsed_slot is not None:
            return self._as_utc(parsed_slot)
        return self._as_utc(checkout_order.active_until)

    def _is_pickup_slot_order(
        self,
        positions: list[MenuPositionDB],
        fulfillment_method: str | None,
        fulfillment_option_index: int | None,
    ) -> bool:
        if not self._is_planned_pickup_fulfillment(
            fulfillment_method,
            fulfillment_option_index,
        ):
            return False

        return self._contains_udka_positions(positions)

    def _contains_udka_positions(self, positions: list[MenuPositionDB]) -> bool:
        return any(
            infer_prep_group_key(position.position_type, position.name) == "udka"
            for position in positions
        )

    def _udka_piece_count_for_positions(self, positions: list[MenuPositionDB]) -> int:
        return sum(
            self._UDKA_PIECES_PER_ITEM
            for position in positions
            if infer_prep_group_key(position.position_type, position.name) == "udka"
        )

    def _resolve_checkout_positions(
        self,
        items: list[CheckoutItemPayload],
    ) -> list[MenuPositionDB]:
        position_ids = sorted(
            {
                item.position_id
                for item in items
                if item.position_id is not None
            }
        )
        if not position_ids:
            return []

        return (
            self.db.query(MenuPositionDB)
            .filter(MenuPositionDB.position_id.in_(position_ids))
            .all()
        )

    def _normalize_pagination(
        self,
        page: int,
        page_size: int,
        default_page_size: int,
        max_page_size: int,
    ) -> tuple[int, int, int]:
        normalized_page = max(1, int(page or 1))
        normalized_page_size = int(page_size or default_page_size)
        normalized_page_size = max(1, min(max_page_size, normalized_page_size))
        offset = (normalized_page - 1) * normalized_page_size
        return normalized_page, normalized_page_size, offset

    def _closed_orders_sort_expression(self):
        return func.coalesce(
            CheckoutOrderDB.receipt_confirmed_at,
            CheckoutOrderDB.active_until,
            CheckoutOrderDB.assigned_at,
            CheckoutOrderDB.created_at,
        )

    def _closed_orders_query(
        self,
        current_user: UserDB,
        normalized_role: str,
        today_only: bool = False,
    ):
        query = self.db.query(CheckoutOrderDB).filter(
            or_(
                CheckoutOrderDB.status == "completed",
                CheckoutOrderDB.processing_status == CHECKOUT_ORDER_STATUS_COMPLETED,
            )
        )
        if normalized_role in {EMPLOYEE_ROLE, DRIVER_ROLE}:
            query = query.filter(
                CheckoutOrderDB.assigned_to_user_id == current_user.user_id,
            )

        if today_only:
            day_start = datetime.utcnow().replace(
                hour=0,
                minute=0,
                second=0,
                microsecond=0,
            )
            next_day = day_start + timedelta(days=1)
            query = query.filter(
                or_(
                    (CheckoutOrderDB.receipt_confirmed_at >= day_start)
                    & (CheckoutOrderDB.receipt_confirmed_at < next_day),
                    (CheckoutOrderDB.active_until >= day_start)
                    & (CheckoutOrderDB.active_until < next_day),
                    (CheckoutOrderDB.assigned_at >= day_start)
                    & (CheckoutOrderDB.assigned_at < next_day),
                    (CheckoutOrderDB.created_at >= day_start)
                    & (CheckoutOrderDB.created_at < next_day),
                )
            )

        return query

    def _ensure_checkout_items_are_available(
        self,
        items: list[CheckoutItemPayload],
    ) -> None:
        position_ids = sorted(
            {
                item.position_id
                for item in items
                if item.position_id is not None
            }
        )
        if not position_ids:
            return

        available_position_ids = {
            position_id
            for (position_id,) in (
                self.db.query(MenuPositionDB.position_id)
                .filter(
                    MenuPositionDB.position_id.in_(position_ids),
                    MenuPositionDB.is_active == True,
                )
                .all()
            )
        }
        missing_position_ids = [
            position_id
            for position_id in position_ids
            if position_id not in available_position_ids
        ]
        if not missing_position_ids:
            return

        raise HTTPException(
            status_code=409,
            detail=(
                "Czesc pozycji nie jest juz dostepna. Odswiez menu i sprobuj ponownie. "
                f"Niedostepne ID: {', '.join(str(position_id) for position_id in missing_position_ids)}."
            ),
        )

    def _resolve_user_id(
        self,
        session_token: str | None,
        user_email: str | None,
    ) -> int | None:
        return self._run_with_connection_retry(
            lambda: self._resolve_user_id_once(
                session_token=session_token,
                user_email=user_email,
            )
        )

    def _resolve_user_id_once(
        self,
        session_token: str | None,
        user_email: str | None,
    ) -> int | None:
        if session_token:
            session = (
                self.db.query(SessionsDB)
                .filter(SessionsDB.session_token == session_token)
                .order_by(SessionsDB.last_seen_at.desc(), SessionsDB.id.desc())
                .first()
            )
            if session is not None:
                self._touch_session_activity(session)
                return session.user_id

        if user_email:
            user = self.db.query(UserDB).filter(UserDB.email == user_email).first()
            if user is not None:
                return user.user_id

        return None

    def _touch_session_activity(self, session: SessionsDB) -> None:
        now = datetime.utcnow()
        reference_time = session.last_seen_at or session.created_at
        if reference_time is not None and now - reference_time < self._SESSION_TOUCH_INTERVAL:
            return

        session.last_seen_at = now
        self.db.commit()

    def _get_active_employees(
        self,
        now: datetime,
    ) -> list[AdminDashboardActiveEmployeeOut]:
        active_since = now - self._EMPLOYEE_ACTIVITY_WINDOW
        session_rows = (
            self.db.query(SessionsDB, UserDB)
            .join(UserDB, UserDB.user_id == SessionsDB.user_id)
            .filter(
                or_(
                    func.lower(func.ltrim(func.rtrim(UserDB.role))) == EMPLOYEE_ROLE,
                    func.lower(func.ltrim(func.rtrim(UserDB.role))) == DRIVER_ROLE,
                ),
                SessionsDB.last_seen_at >= active_since,
            )
            .order_by(SessionsDB.last_seen_at.desc(), SessionsDB.id.desc())
            .all()
        )

        active_employees: list[AdminDashboardActiveEmployeeOut] = []
        seen_user_ids: set[int] = set()
        for session, user in session_rows:
            if user.user_id in seen_user_ids:
                continue
            seen_user_ids.add(user.user_id)

            email = (user.email or "").strip()
            display_name = self._resolve_employee_display_name(user)
            active_employees.append(
                AdminDashboardActiveEmployeeOut(
                    user_id=user.user_id,
                    email=email,
                    display_name=display_name,
                    initials=self._build_employee_initials(
                        display_name=display_name,
                        email=email,
                    ),
                    last_seen_at=self._as_utc(
                        session.last_seen_at or session.created_at or now,
                    ),
                )
            )

        return active_employees

    def _get_currently_available_staff_presence(
        self,
        now: datetime,
    ) -> list[AdminStaffPresencePersonOut]:
        return [
            AdminStaffPresencePersonOut(
                user_id=employee.user_id,
                email=employee.email,
                display_name=employee.display_name,
                initials=employee.initials,
                last_seen_at=employee.last_seen_at,
                is_currently_available=True,
            )
            for employee in self._get_active_employees(now=now)
        ]

    def _get_recently_available_staff_presence(
        self,
        now: datetime,
        exclude_user_ids: set[int],
    ) -> list[AdminStaffPresencePersonOut]:
        recent_since = now - timedelta(hours=1)
        active_since = now - self._EMPLOYEE_ACTIVITY_WINDOW
        session_rows = (
            self.db.query(SessionsDB, UserDB)
            .join(UserDB, UserDB.user_id == SessionsDB.user_id)
            .filter(
                self._staff_role_filter(),
                SessionsDB.last_seen_at >= recent_since,
                SessionsDB.last_seen_at < active_since,
            )
            .order_by(SessionsDB.last_seen_at.desc(), SessionsDB.id.desc())
            .all()
        )

        recent_employees: list[AdminStaffPresencePersonOut] = []
        seen_user_ids = set(exclude_user_ids)
        for session, user in session_rows:
            if user.user_id in seen_user_ids:
                continue
            seen_user_ids.add(user.user_id)
            recent_employees.append(
                self._staff_presence_person_from_user(
                    user=user,
                    last_seen_at=session.last_seen_at or session.created_at,
                    is_currently_available=False,
                )
            )

        return recent_employees

    def _search_staff_presence(
        self,
        query: str | None,
        current_user_ids: set[int],
    ) -> list[AdminStaffPresencePersonOut]:
        latest_seen_rows = (
            self.db.query(
                SessionsDB.user_id.label("user_id"),
                func.max(SessionsDB.last_seen_at).label("last_seen_at"),
            )
            .group_by(SessionsDB.user_id)
            .all()
        )
        latest_seen_by_user_id = {
            int(row.user_id): row.last_seen_at
            for row in latest_seen_rows
            if row.user_id is not None
        }

        normalized_query = (query or "").strip().lower()
        users = self.db.query(UserDB).filter(self._staff_role_filter()).all()

        results = [
            self._staff_presence_person_from_user(
                user=user,
                last_seen_at=latest_seen_by_user_id.get(int(user.user_id)),
                is_currently_available=int(user.user_id) in current_user_ids,
            )
            for user in users
            if not normalized_query
            or normalized_query
            in f"{self._resolve_employee_display_name(user)} {(user.email or '').strip()}".lower()
        ]

        results.sort(
            key=lambda person: (
                person.last_seen_at is None,
                -(person.last_seen_at.timestamp() if person.last_seen_at else 0),
                (person.display_name or person.email).lower(),
                person.email.lower(),
            ),
        )
        return results

    def _staff_presence_person_from_user(
        self,
        user: UserDB,
        last_seen_at: datetime | None,
        is_currently_available: bool,
    ) -> AdminStaffPresencePersonOut:
        email = (user.email or "").strip()
        display_name = self._resolve_employee_display_name(user)
        return AdminStaffPresencePersonOut(
            user_id=user.user_id,
            email=email,
            display_name=display_name,
            initials=self._build_employee_initials(
                display_name=display_name,
                email=email,
            ),
            last_seen_at=self._as_utc(last_seen_at),
            is_currently_available=is_currently_available,
        )

    def _staff_role_filter(self):
        return or_(
            func.lower(func.ltrim(func.rtrim(UserDB.role))) == EMPLOYEE_ROLE,
            func.lower(func.ltrim(func.rtrim(UserDB.role))) == DRIVER_ROLE,
        )

    def _resolve_employee_display_name(self, user: UserDB) -> str:
        if user.name and user.name.strip():
            return user.name.strip()

        email = (user.email or "").strip()
        if not email:
            return f"Pracownik #{user.user_id}"

        local_part = email.split("@", 1)[0]
        normalized = " ".join(
            token
            for token in local_part.replace(".", " ").replace("_", " ").replace("-", " ").split()
            if token
        )
        return normalized.title() if normalized else email

    def _build_employee_initials(
        self,
        display_name: str,
        email: str,
    ) -> str:
        source = display_name.strip() or email.split("@", 1)[0].strip()
        if not source:
            return "?"

        parts = [
            part
            for part in source.replace(".", " ").replace("_", " ").replace("-", " ").split()
            if part
        ]
        if len(parts) >= 2:
            return f"{parts[0][0]}{parts[1][0]}".upper()

        compact = "".join(ch for ch in source if ch.isalnum())
        return compact[:2].upper() if compact else "?"

    def _require_admin_user(
        self,
        session_token: str | None,
        user_email: str | None,
    ) -> UserDB:
        user_id = self._resolve_user_id(
            session_token=session_token,
            user_email=user_email,
        )
        if user_id is None:
            raise HTTPException(status_code=401, detail="Brak autoryzacji administratora.")

        user = self.db.query(UserDB).filter(UserDB.user_id == user_id).first()
        normalized_role = (user.role or "").strip().lower()
        if normalized_role not in {ADMIN_ROLE, EMPLOYEE_ROLE, DRIVER_ROLE}:
            raise HTTPException(
                status_code=403,
                detail="Ten panel jest dostepny tylko dla administratora, pracownika lub kierowcy.",
            )

        return user

    def _require_admin_role(
        self,
        session_token: str | None,
        user_email: str | None,
    ) -> UserDB:
        user = self._require_admin_user(
            session_token=session_token,
            user_email=user_email,
        )
        normalized_role = (user.role or "").strip().lower()
        if normalized_role != ADMIN_ROLE:
            raise HTTPException(
                status_code=403,
                detail="Ta funkcja jest dostepna tylko dla administratora.",
            )
        return user

    def _normalize_processing_status(self, processing_status: str) -> str:
        normalized = (processing_status or "").strip().lower()
        allowed_statuses = {
            CHECKOUT_ORDER_STATUS_UNASSIGNED,
            CHECKOUT_ORDER_STATUS_ASSIGNED,
            CHECKOUT_ORDER_STATUS_COMPLETED,
        }
        if normalized not in allowed_statuses:
            raise HTTPException(status_code=400, detail="Nieobslugiwany status obslugi zamowienia.")
        return normalized

    def _normalize_operator_verification_stage(
        self,
        processing_status: str,
        verification_stage: str | None,
    ) -> str | None:
        normalized = (verification_stage or "").strip().lower()
        if not normalized:
            return None

        if processing_status != CHECKOUT_ORDER_STATUS_ASSIGNED:
            raise HTTPException(
                status_code=400,
                detail="Etap realizacji mozna ustawic tylko dla zamowienia podjetego.",
            )

        allowed_stages = {
            "assigned",
            "in_oven",
            "ready_for_delivery",
            "on_the_way",
        }
        if normalized not in allowed_stages:
            raise HTTPException(
                status_code=400,
                detail="Nieobslugiwany etap realizacji zamowienia.",
            )

        return normalized

    def _is_order_visible_on_admin_board(self, checkout_order: CheckoutOrderDB) -> bool:
        return not self._is_order_closed(checkout_order)

    def _is_order_closed(self, checkout_order: CheckoutOrderDB) -> bool:
        return (
            checkout_order.status == "completed"
            or checkout_order.processing_status == CHECKOUT_ORDER_STATUS_COMPLETED
        )

    def _build_admin_order(
        self,
        checkout_order: CheckoutOrderDB,
        customer_email: str | None,
        now: datetime,
        current_user_id: int | None = None,
        assigned_operator_email: str | None = None,
        current_oven_load: int | None = None,
        current_udka_oven_load: int | None = None,
    ) -> AdminDashboardOrderOut:
        remaining_eta_minutes = self._remaining_eta_minutes(
            checkout_order=checkout_order,
            now=now,
            include_oven_queue=True,
            current_oven_load=current_oven_load,
            current_udka_oven_load=current_udka_oven_load,
        )

        item_count = sum((item.quantity or 1) for item in checkout_order.items)
        item_names = [
            item.name if (item.quantity or 1) == 1 else f"{item.name} x{item.quantity}"
            for item in checkout_order.items
        ]
        unread_customer_message_count = sum(
            1
            for message in checkout_order.chat_messages
            if (message.sender_role or "").strip().lower() == "customer"
            and message.staff_read_at is None
        )
        supports_progress_updates = self._order_supports_progress_updates(checkout_order)
        oven_kind = self._order_oven_kind(checkout_order)
        oven_slot_count = self._order_oven_slot_count(checkout_order)
        oven_load = self._get_effective_oven_load(
            checkout_order=checkout_order,
            current_oven_load=current_oven_load,
            current_udka_oven_load=current_udka_oven_load,
        )
        oven_capacity = self._oven_capacity_for_kind(oven_kind)

        return AdminDashboardOrderOut(
            checkout_order_id=checkout_order.checkout_order_id,
            verification_id=checkout_order.verification_id,
            processing_status=checkout_order.processing_status,
            lifecycle_status=checkout_order.status,
            verification_stage=checkout_order.verification_stage,
            created_at=self._as_utc(checkout_order.created_at),
            closed_at=self._as_utc(self._resolve_closed_at(checkout_order)),
            active_until=self._as_utc(checkout_order.active_until),
            remaining_eta_minutes=remaining_eta_minutes,
            customer_email=customer_email,
            payment_method=checkout_order.payment_method,
            fulfillment_method=checkout_order.fulfillment_method,
            total_amount=float(checkout_order.total_amount),
            item_count=item_count,
            item_names=item_names,
            items=[
                AdminDashboardOrderItemOut(
                    name=item.name,
                    quantity=item.quantity or 1,
                    price=float(item.price) if item.price is not None else None,
                    description=item.description,
                )
                for item in checkout_order.items
            ],
            address_title=checkout_order.address_title,
            address_subtitle=checkout_order.address_subtitle,
            notes=checkout_order.notes,
            supports_progress_updates=supports_progress_updates,
            oven_kind=oven_kind,
            can_mark_in_oven=(
                supports_progress_updates
                and oven_slot_count > 0
                and oven_load + oven_slot_count <= oven_capacity
            ),
            oven_slot_count=oven_slot_count,
            oven_load=oven_load,
            oven_capacity=oven_capacity,
            unread_customer_message_count=unread_customer_message_count,
            assigned_to_me=(
                current_user_id is not None
                and checkout_order.assigned_to_user_id == current_user_id
            ),
            assigned_operator_email=assigned_operator_email,
        )

    def _order_supports_progress_updates(
        self,
        checkout_order: CheckoutOrderDB,
    ) -> bool:
        if not checkout_order.items:
            return True

        item_signatures = [
            f"{(item.name or '').strip().lower()} {(item.description or '').strip().lower()}"
            for item in checkout_order.items
        ]
        if not any(item_signatures):
            return True

        return any(self._item_supports_oven_stage(signature) for signature in item_signatures)

    def _item_supports_oven_stage(self, item_signature: str) -> bool:
        normalized = (item_signature or "").strip().lower()
        if not normalized:
            return False

        no_oven_keywords = (
            "mroz",
            "frozen",
            "odgrzan",
            "hermetycz",
            "lod",
            "ice cream",
            "gelato",
            "cola",
            "sprite",
            "fanta",
            "pepsi",
            "napoj",
            "woda",
            "sok",
            "kawa",
            "herbata",
        )
        return not any(keyword in normalized for keyword in no_oven_keywords)

    def _item_is_udka_signature(self, item_signature: str) -> bool:
        normalized = (item_signature or "").strip().lower()
        return "udk" in normalized or "chicken leg" in normalized

    def _is_in_oven_stage(self, checkout_order: CheckoutOrderDB) -> bool:
        return (checkout_order.verification_stage or "").strip().lower() in {"in_oven", "oven"}

    def _order_oven_kind(self, checkout_order: CheckoutOrderDB) -> str:
        if self._order_udka_piece_count(checkout_order) > 0:
            return "udka"
        if self._order_supports_progress_updates(checkout_order):
            return "zapiekanki"
        return "none"

    def _oven_capacity_for_kind(self, oven_kind: str) -> int:
        if oven_kind == "udka":
            return self._UDKA_OVEN_CAPACITY
        if oven_kind == "zapiekanki":
            return self._OVEN_CAPACITY
        return 0

    def _order_oven_slot_count(self, checkout_order: CheckoutOrderDB) -> int:
        oven_kind = self._order_oven_kind(checkout_order)
        if oven_kind == "udka":
            return self._order_udka_piece_count(checkout_order)
        if oven_kind == "none":
            return 0

        if not checkout_order.items:
            return 0

        oven_items_count = 0
        for item in checkout_order.items:
            item_signature = (
                f"{(item.name or '').strip().lower()} "
                f"{(item.description or '').strip().lower()}"
            )
            if not self._item_supports_oven_stage(item_signature):
                continue
            oven_items_count += max(1, int(item.quantity or 1))

        if oven_items_count <= 0:
            return 0
        return min(self._OVEN_CAPACITY, oven_items_count)

    def _order_udka_piece_count(self, checkout_order: CheckoutOrderDB) -> int:
        if not checkout_order.items:
            return 0

        udka_piece_count = 0
        for item in checkout_order.items:
            item_signature = (
                f"{(item.name or '').strip().lower()} "
                f"{(item.description or '').strip().lower()}"
            )
            if not self._item_is_udka_signature(item_signature):
                continue
            udka_piece_count += max(1, int(item.quantity or 1)) * self._UDKA_PIECES_PER_ITEM

        return min(self._UDKA_OVEN_CAPACITY, udka_piece_count) if udka_piece_count > 0 else 0

    def _get_current_oven_load(
        self,
        exclude_checkout_order_id: int | None = None,
    ) -> int:
        query = (
            self.db.query(CheckoutOrderDB)
            .options(joinedload(CheckoutOrderDB.items))
            .filter(
                CheckoutOrderDB.status != "completed",
                CheckoutOrderDB.processing_status != CHECKOUT_ORDER_STATUS_COMPLETED,
                CheckoutOrderDB.verification_stage.in_(("in_oven", "oven")),
            )
        )
        if exclude_checkout_order_id is not None:
            query = query.filter(
                CheckoutOrderDB.checkout_order_id != exclude_checkout_order_id,
            )

        return sum(
            self._order_oven_slot_count(checkout_order)
            for checkout_order in query.all()
            if self._order_oven_kind(checkout_order) == "zapiekanki"
        )

    def _get_udka_slot_load(
        self,
        slot_datetime: datetime,
        exclude_checkout_order_id: int | None = None,
    ) -> int:
        slot_utc = self._as_naive_utc(slot_datetime)
        if slot_utc is None:
            return 0
        slot_window_end = slot_utc + timedelta(minutes=1)

        query = (
            self.db.query(CheckoutOrderDB)
            .options(joinedload(CheckoutOrderDB.items))
            .filter(
                CheckoutOrderDB.status != "completed",
                CheckoutOrderDB.processing_status != CHECKOUT_ORDER_STATUS_COMPLETED,
                CheckoutOrderDB.active_until >= slot_utc,
                CheckoutOrderDB.active_until < slot_window_end,
            )
        )
        if exclude_checkout_order_id is not None:
            query = query.filter(
                CheckoutOrderDB.checkout_order_id != exclude_checkout_order_id,
            )

        return sum(
            self._order_udka_piece_count(checkout_order)
            for checkout_order in query.all()
            if self._order_oven_kind(checkout_order) == "udka"
        )

    def _get_effective_oven_load(
        self,
        checkout_order: CheckoutOrderDB,
        current_oven_load: int | None = None,
        current_udka_oven_load: int | None = None,
    ) -> int:
        oven_kind = self._order_oven_kind(checkout_order)
        if oven_kind == "udka":
            slot_datetime = self._scheduled_pickup_at_for_order(checkout_order)
            if slot_datetime is None:
                return 0
            resolved_udka_load = (
                self._get_udka_slot_load(slot_datetime, exclude_checkout_order_id=checkout_order.checkout_order_id)
                if current_udka_oven_load is None or self._is_in_oven_stage(checkout_order)
                else current_udka_oven_load
            )
            return resolved_udka_load

        resolved_oven_load = (
            self._get_current_oven_load()
            if current_oven_load is None
            else current_oven_load
        )
        if self._is_in_oven_stage(checkout_order):
            return max(0, resolved_oven_load - self._order_oven_slot_count(checkout_order))
        return resolved_oven_load

    def _remaining_eta_minutes(
        self,
        checkout_order: CheckoutOrderDB,
        now: datetime,
        include_oven_queue: bool,
        current_oven_load: int | None = None,
        current_udka_oven_load: int | None = None,
    ) -> int:
        if checkout_order.active_until is None:
            return 0

        remaining_seconds = max(
            0.0,
            (checkout_order.active_until - now).total_seconds(),
        )
        remaining_eta_minutes = max(0, int((remaining_seconds + 59) // 60))
        if not include_oven_queue:
            return remaining_eta_minutes

        return remaining_eta_minutes + self._oven_queue_delay_minutes(
            checkout_order=checkout_order,
            current_oven_load=current_oven_load,
            current_udka_oven_load=current_udka_oven_load,
        )

    def _oven_queue_delay_minutes(
        self,
        checkout_order: CheckoutOrderDB,
        current_oven_load: int | None = None,
        current_udka_oven_load: int | None = None,
    ) -> int:
        if not self._order_supports_progress_updates(checkout_order):
            return 0
        if self._order_oven_kind(checkout_order) == "udka":
            return 0
        if checkout_order.processing_status != CHECKOUT_ORDER_STATUS_ASSIGNED:
            return 0
        if self._is_in_oven_stage(checkout_order):
            return 0
        if self._is_ready_for_delivery_stage(checkout_order):
            return 0
        if (checkout_order.verification_stage or "").strip().lower() not in {
            "",
            "accepted",
            "assigned",
        }:
            return 0

        order_oven_slot_count = self._order_oven_slot_count(checkout_order)
        if order_oven_slot_count <= 0:
            return 0

        oven_load = self._get_effective_oven_load(
            checkout_order=checkout_order,
            current_oven_load=current_oven_load,
            current_udka_oven_load=current_udka_oven_load,
        )
        overflow_slots = (oven_load + order_oven_slot_count) - self._OVEN_CAPACITY
        if overflow_slots <= 0:
            return 0

        delayed_batches = max(
            1,
            (overflow_slots + self._OVEN_CAPACITY - 1) // self._OVEN_CAPACITY,
        )
        return delayed_batches * self._OVEN_QUEUE_DELAY_MINUTES

    def _serialize_checkout_message(
        self,
        message: CheckoutOrderMessageDB,
    ) -> CheckoutOrderMessageOut:
        return CheckoutOrderMessageOut(
            checkout_order_message_id=message.checkout_order_message_id,
            checkout_order_id=message.checkout_order_id,
            sender_role=message.sender_role,
            author_label=message.author_label,
            message=message.message,
            created_at=self._as_utc(message.created_at),
            staff_read_at=self._as_utc(message.staff_read_at),
        )

    def _chat_sender_role_for_user(self, normalized_role: str) -> str:
        return "staff" if normalized_role in {ADMIN_ROLE, EMPLOYEE_ROLE, DRIVER_ROLE} else "customer"

    def _chat_author_label(self, user: UserDB, sender_role: str) -> str:
        if sender_role == "staff":
            return self._resolve_employee_display_name(user)
        if user.name and user.name.strip():
            return user.name.strip()
        return "Klient"

    def _require_checkout_order_access(
        self,
        checkout_order_id: int,
        session_token: str | None,
        user_email: str | None,
        allow_staff: bool,
    ) -> tuple[CheckoutOrderDB, UserDB, str]:
        user_id = self._resolve_user_id(
            session_token=session_token,
            user_email=user_email,
        )
        if user_id is None:
            raise HTTPException(status_code=401, detail="Brak autoryzacji uzytkownika.")

        current_user = self.db.query(UserDB).filter(UserDB.user_id == user_id).first()
        if current_user is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono uzytkownika.")

        checkout_order = (
            self.db.query(CheckoutOrderDB)
            .filter(CheckoutOrderDB.checkout_order_id == checkout_order_id)
            .first()
        )
        if checkout_order is None:
            raise HTTPException(status_code=404, detail="Nie znaleziono zamowienia checkout.")

        normalized_role = (current_user.role or "").strip().lower()
        if normalized_role in {ADMIN_ROLE, EMPLOYEE_ROLE, DRIVER_ROLE} and allow_staff:
            return checkout_order, current_user, normalized_role

        if checkout_order.user_id != current_user.user_id:
            raise HTTPException(
                status_code=403,
                detail="To zamowienie nie nalezy do zalogowanego uzytkownika.",
            )

        return checkout_order, current_user, normalized_role

    def _ensure_staff_can_access_order_messages(
        self,
        checkout_order: CheckoutOrderDB,
        current_user: UserDB,
        normalized_role: str,
    ) -> None:
        if normalized_role == ADMIN_ROLE:
            return
        if normalized_role not in {EMPLOYEE_ROLE, DRIVER_ROLE}:
            raise HTTPException(
                status_code=403,
                detail="Tylko przypisany pracownik lub kierowca moze obslugiwac wiadomosci dla tego zamowienia.",
            )
        if checkout_order.assigned_to_user_id != current_user.user_id:
            raise HTTPException(
                status_code=403,
                detail="To zamowienie nie jest przypisane do zalogowanego operatora.",
            )

    def _resolve_closed_at(self, checkout_order: CheckoutOrderDB) -> datetime | None:
        if not self._is_order_closed(checkout_order):
            return None

        return (
            checkout_order.receipt_confirmed_at
            or checkout_order.active_until
            or checkout_order.assigned_at
            or checkout_order.created_at
        )

    def _run_with_connection_retry(self, operation):
        try:
            return operation()
        except OperationalError as exc:
            if not self._is_disconnect_error(exc):
                raise

            self._reset_broken_session()
            return operation()

    def _reset_broken_session(self) -> None:
        try:
            self.db.rollback()
        except SQLAlchemyError:
            pass

        self.db.invalidate()

    def _is_disconnect_error(self, exc: OperationalError) -> bool:
        message = str(exc).lower()
        disconnect_markers = (
            "communication link failure",
            "existing connection was forcibly closed by the remote host",
            "tcp provider",
            "08s01",
            "10054",
        )
        return any(marker in message for marker in disconnect_markers)
