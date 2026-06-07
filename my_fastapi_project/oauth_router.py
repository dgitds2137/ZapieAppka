from fastapi import APIRouter, Depends
from pydantic import EmailStr
from sqlalchemy.orm import Session

from models import AuthSessionOut, OAuthAuthorizationStartOut, OAuthCodeExchangeIn


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

    return r
