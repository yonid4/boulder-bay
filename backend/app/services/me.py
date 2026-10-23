"""The authenticated user's own data. Currently the profile only."""

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import UserProfile
from app.db import models as db


class ProfileNotFoundError(Exception):
    """No `profiles` row exists for the user; the signup trigger should make this impossible."""


async def get_profile(session: AsyncSession, user_id: UUID) -> UserProfile:
    """Read the user's profile by primary key."""

    row = await session.get(db.Profile, user_id)
    if row is None:
        raise ProfileNotFoundError(user_id)
    return UserProfile(id=row.id, display_name=row.display_name)
