from datetime import datetime
import uuid

from fastapi import HTTPException
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from models import (
    CheckoutOrderDB,
    CheckoutOrderItemDB,
    CheckoutVerificationIn,
    CheckoutVerificationOut,
)


class CheckoutService:
    _METHOD_MESSAGES = {
        "BLIK": "Wstepna weryfikacja kodu BLIK zostanie podpieta w kolejnym kroku.",
        "Google Pay": "Wstepna weryfikacja Google Pay zostanie podpieta w kolejnym kroku.",
        "Apple Pay": "Wstepna weryfikacja Apple Pay zostanie podpieta w kolejnym kroku.",
    }

    def __init__(self, db: Session):
        self.db = db

    def create_checkout_verification(
        self,
        payload: CheckoutVerificationIn,
    ) -> CheckoutVerificationOut:
        verification_id = f"chk_{uuid.uuid4().hex[:12]}"
        created_at = datetime.utcnow()

        checkout_order = CheckoutOrderDB(
            verification_id=verification_id,
            status="pending_verification",
            verification_stage="pre_verification",
            payment_method=payload.payment_method,
            currency=payload.currency,
            total_amount=payload.total_amount,
            eta_minutes=payload.eta_minutes,
            fulfillment_method=payload.fulfillment_method,
            fulfillment_option_index=payload.fulfillment_option_index,
            address_option_index=payload.address_option_index,
            address_title=payload.address.title,
            address_subtitle=payload.address.subtitle,
            address_eta_label=payload.address.eta_label,
            notes=payload.notes,
            client_created_at=payload.created_at,
            created_at=created_at,
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

            self.db.commit()
            self.db.refresh(checkout_order)
        except SQLAlchemyError as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail="Nie udalo sie zapisac zamowienia checkout.",
            ) from exc

        return CheckoutVerificationOut(
            verification_id=verification_id,
            saved_order_id=checkout_order.checkout_order_id,
            status=checkout_order.status,
            payment_method=payload.payment_method,
            verification_stage=checkout_order.verification_stage,
            message=self._METHOD_MESSAGES.get(
                payload.payment_method,
                "Wstepna weryfikacja metody platnosci zostanie podpieta w kolejnym kroku.",
            ),
            created_at=checkout_order.created_at,
            received_order=payload,
        )
