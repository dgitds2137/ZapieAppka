import base64

from fastapi import APIRouter, Depends, Form, HTTPException
from sqlalchemy.orm import Session

from models import (
    AdminCatalogAddonOut,
    AdminCatalogDeliveryMinimumUpdateIn,
    AdminCatalogOpeningHoursUpdateIn,
    AdminCatalogDeliveryOriginAddressUpdateIn,
    AdminCatalogDeliveryRadiusUpdateIn,
    AdminCatalogItemUpdateIn,
    AdminCatalogOut,
    AdminCatalogPositionOut,
    AdminClosedOrdersPageOut,
    AdminDashboardOrderOut,
    AdminDashboardOut,
    AdminOrderStatusUpdateIn,
    AdminStaffPresenceOut,
    CheckoutHistoryPageOut,
    CheckoutOrderMessageCreateIn,
    CheckoutOrderMessageOut,
    CheckoutOrderMessagesReadIn,
    CheckoutOrderMessagesReadOut,
    CheckoutPickupLocationOut,
    CheckoutPickupSlotEstimateIn,
    CheckoutPickupSlotEstimateOut,
    CheckoutReceiptConfirmationIn,
    CheckoutVerificationIn,
    CheckoutVerificationOut,
    DeliveryAddressValidationIn,
    DeliveryAddressValidationOut,
    MenuAddonSchema,
    OpeningHoursOut,
    PrepTimeSettingOut,
    PrepTimeSettingUpdateIn,
    UserSchema,
)


def routes(MenuService, UserService, CheckoutService, get_db):
    r = APIRouter()

    @r.post("/login")
    def login(email: str = Form(...), password: str = Form(...), db: Session = Depends(get_db)):
        decoded_pwd = base64.b64decode(password.encode("utf-8")).decode("utf-8")
        return UserService(db).login(email, decoded_pwd)

    @r.get("/get_user/{email}", response_model=UserSchema)
    def get_user(email: str, db: Session = Depends(get_db)):
        user = UserService(db).get_user(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user

    @r.get("/positions")
    def get_positions(db: Session = Depends(get_db)):
        return MenuService(db).get_all_positions()

    @r.get("/opening-hours", response_model=OpeningHoursOut)
    def get_opening_hours(db: Session = Depends(get_db)):
        return CheckoutService(db).get_opening_hours()

    @r.get("/position/{position_id}/addons", response_model=list[MenuAddonSchema])
    def get_position_addons(position_id: int, db: Session = Depends(get_db)):
        return MenuService(db).get_position_addons(position_id)

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

    @r.get("/checkout/pickup-location", response_model=CheckoutPickupLocationOut)
    def get_pickup_location(db: Session = Depends(get_db)):
        return CheckoutService(db).get_pickup_location()

    @r.post(
        "/checkout/validate-delivery-address",
        response_model=DeliveryAddressValidationOut,
    )
    def validate_delivery_address(
        payload: DeliveryAddressValidationIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).validate_delivery_address(payload)

    @r.post("/checkout/pickup-slot-estimate", response_model=CheckoutPickupSlotEstimateOut)
    def get_pickup_slot_estimate(
        payload: CheckoutPickupSlotEstimateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_pickup_slot_estimate(payload)

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

    @r.get("/admin/staff-presence", response_model=AdminStaffPresenceOut)
    def get_admin_staff_presence(
        session_token: str | None = None,
        email: str | None = None,
        q: str | None = None,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).get_admin_staff_presence(
            session_token=session_token,
            user_email=email,
            query=q,
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

    @r.patch(
        "/admin/catalog/delivery-radius",
        response_model=AdminCatalogOut,
    )
    def update_admin_delivery_radius(
        payload: AdminCatalogDeliveryRadiusUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_delivery_radius(
            payload=payload,
        )

    @r.patch(
        "/admin/catalog/opening-hours",
        response_model=AdminCatalogOut,
    )
    def update_admin_opening_hours(
        payload: AdminCatalogOpeningHoursUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_opening_hours(
            payload=payload,
        )

    @r.patch(
        "/admin/catalog/delivery-origin-address",
        response_model=AdminCatalogOut,
    )
    def update_admin_delivery_origin_address(
        payload: AdminCatalogDeliveryOriginAddressUpdateIn,
        db: Session = Depends(get_db),
    ):
        return CheckoutService(db).update_delivery_origin_address(
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
