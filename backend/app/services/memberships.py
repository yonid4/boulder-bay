"""Gym memberships.

A slug is resolved to a `gym_id` once, at the edge, and only active gyms resolve. Identity
always comes from the caller's JWT, never from a path. Writes are idempotent: adding an
existing membership or removing an absent one succeeds silently.
"""

from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import models as db


class GymNotFoundError(Exception):
    """The slug names no active gym."""

    def __init__(self, slug: str) -> None:
        super().__init__(f"No active gym with slug {slug!r}")
        self.slug = slug


async def _active_gym_id(session: AsyncSession, slug: str) -> int:
    gym_id = await session.scalar(select(db.Gym.id).where(db.Gym.slug == slug, db.Gym.is_active))
    if gym_id is None:
        raise GymNotFoundError(slug)
    return gym_id


async def list_membership_slugs(session: AsyncSession, *, user_id: UUID) -> list[str]:
    """Slugs of the user's active member gyms, ordered by gym name."""

    stmt = (
        select(db.Gym.slug)
        .join(db.GymMembership, db.GymMembership.gym_id == db.Gym.id)
        .where(db.GymMembership.user_id == user_id, db.Gym.is_active)
        .order_by(db.Gym.name)
    )
    return list((await session.scalars(stmt)).all())


async def member_gym_ids(session: AsyncSession, *, user_id: UUID) -> set[int]:
    """Ids of every gym the user belongs to, active or not, in one query."""

    stmt = select(db.GymMembership.gym_id).where(db.GymMembership.user_id == user_id)
    return set((await session.scalars(stmt)).all())


async def add_membership(session: AsyncSession, *, user_id: UUID, slug: str) -> None:
    """Add a gym to the user's memberships; a no-op if already present."""

    gym_id = await _active_gym_id(session, slug)
    await session.execute(
        insert(db.GymMembership).values(user_id=user_id, gym_id=gym_id).on_conflict_do_nothing()
    )
    await session.commit()


async def remove_membership(session: AsyncSession, *, user_id: UUID, slug: str) -> None:
    """Remove a gym from the user's memberships; a no-op if absent."""

    gym_id = await _active_gym_id(session, slug)
    await session.execute(
        delete(db.GymMembership).where(
            db.GymMembership.user_id == user_id, db.GymMembership.gym_id == gym_id
        )
    )
    await session.commit()
