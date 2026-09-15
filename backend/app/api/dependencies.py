"""Shared FastAPI dependencies."""

import asyncio
from functools import lru_cache
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError, PyJWKClient, PyJWKClientConnectionError, PyJWKClientError
from pydantic import BaseModel

from app.config import get_settings

JWT_ALGORITHM = "ES256"
JWT_AUDIENCE = "authenticated"
INVALID_TOKEN_DETAIL = "Invalid or expired authentication token"


class AuthenticatedUser(BaseModel):
    """Identity made available after a Supabase JWT has been verified."""

    id: UUID


bearer_scheme = HTTPBearer()


@lru_cache
def get_jwks_client() -> PyJWKClient:
    """Build one caching JWKS client for the configured Supabase project."""

    return PyJWKClient(get_settings().jwks_url)


async def require_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Security(bearer_scheme)],
) -> AuthenticatedUser:
    """Verify a Supabase access token and return its user identity."""

    token = credentials.credentials
    settings = get_settings()

    try:
        signing_key = await asyncio.to_thread(get_jwks_client().get_signing_key_from_jwt, token)
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=[JWT_ALGORITHM],
            audience=JWT_AUDIENCE,
            issuer=f"{settings.supabase_url}/auth/v1",
            options={"require": ["sub", "iss", "aud", "exp"]},
        )
        subject = claims["sub"]
        if not isinstance(subject, str):
            raise ValueError("JWT subject must be a string")
        return AuthenticatedUser(id=UUID(subject))
    except PyJWKClientConnectionError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unavailable",
        ) from error
    except (InvalidTokenError, PyJWKClientError, KeyError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=INVALID_TOKEN_DETAIL,
            headers={"WWW-Authenticate": "Bearer"},
        ) from error


CurrentUser = Annotated[AuthenticatedUser, Security(require_user)]
