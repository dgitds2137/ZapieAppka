from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import EmailStr
from sqlalchemy.orm import Session

from models import (
    AppleAuthorizationStartOut,
    AuthSessionOut,
    GoogleIdTokenExchangeIn,
    OAuthAuthorizationStartOut,
    OAuthCodeExchangeIn,
)


def oauth_routes(GoogleOAuthService, get_db):
    r = APIRouter()

    @r.get("/google-auth/start", response_model=OAuthAuthorizationStartOut)
    def google_auth_start(
        redirect_uri: str,
        email: EmailStr | None = None,
        db: Session = Depends(get_db),
    ):
        return GoogleOAuthService(db).start_authorization(
            redirect_uri=redirect_uri,
            email=email,
        )

    @r.post("/google-auth/callback", response_model=AuthSessionOut)
    def google_auth_callback(
        payload: OAuthCodeExchangeIn,
        db: Session = Depends(get_db),
    ):
        return GoogleOAuthService(db).exchange_code(payload)

    @r.post("/google-auth/mobile", response_model=AuthSessionOut)
    def google_auth_mobile(
        payload: GoogleIdTokenExchangeIn,
        db: Session = Depends(get_db),
    ):
        return GoogleOAuthService(db).exchange_id_token(payload)

    @r.get("/apple-auth/start", response_model=AppleAuthorizationStartOut)
    def apple_auth_start(
        redirect_uri: str,
        email: EmailStr | None = None,
        db: Session = Depends(get_db),
    ):
        return GoogleOAuthService(db).build_apple_service().start_authorization(
            redirect_uri=redirect_uri,
            email=email,
        )

    @r.post("/apple-auth/callback", response_model=AuthSessionOut)
    def apple_auth_callback(
        payload: OAuthCodeExchangeIn,
        db: Session = Depends(get_db),
    ):
        return GoogleOAuthService(db).build_apple_service().exchange_code(payload)

    @r.api_route("/apple-auth/return", methods=["GET", "POST"], include_in_schema=False)
    async def apple_auth_return(
        request: Request,
        db: Session = Depends(get_db),
    ):
        if request.method.upper() == "POST":
            payload = dict(await request.form())
        else:
            payload = dict(request.query_params)

        state = payload.get("state")
        if state is None or str(state).strip() == "":
            raise HTTPException(status_code=400, detail="Brakuje state logowania Apple.")

        redirect_url = GoogleOAuthService(db).build_apple_service().build_frontend_callback_redirect(
            state=str(state),
            code=(str(payload.get("code")).strip() if payload.get("code") is not None else None),
            user=(str(payload.get("user")).strip() if payload.get("user") is not None else None),
            error=(str(payload.get("error")).strip() if payload.get("error") is not None else None),
            error_description=(
                str(payload.get("error_description")).strip()
                if payload.get("error_description") is not None
                else None
            ),
        )
        return RedirectResponse(url=redirect_url, status_code=302)

    return r
