"""Authenticated user profile models."""

from uuid import UUID

from pydantic import BaseModel


class UserProfile(BaseModel):
    id: UUID
    display_name: str | None = None
