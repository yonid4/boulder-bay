"""Shared FastAPI dependencies.

JWT verification is deliberately not implemented yet. Keeping the dependency in
the route signatures makes the Bearer-authenticated contract visible in OpenAPI
without pretending that an unverified token identifies a user.
"""

from typing import Annotated
from uuid import UUID

from fastapi import HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel


class AuthenticatedUser(BaseModel):
    """Identity made available after a Supabase JWT has been verified."""

    id: UUID


bearer_scheme = HTTPBearer()


def require_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Security(bearer_scheme)],
) -> AuthenticatedUser:
    """Require the future verified Supabase identity for an API request."""

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Supabase JWT verification is not implemented",
    )


CurrentUser = Annotated[AuthenticatedUser, Security(require_user)]
