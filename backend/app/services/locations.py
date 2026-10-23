"""Saved locations ("places").

Every query is scoped by the caller's `user_id` from the JWT, so another user's location id
behaves exactly like a missing one. Rules from `boulder_bay_v1_design.md` §4:

- The user's first location becomes the default whatever its kind; there is no count cap.
- Promoting clears the current default *before* setting the new one, in one transaction,
  because `saved_locations_one_default_idx` is a partial unique index (schema §2.7).
- The last remaining location can't be deleted. Deleting the default promotes the oldest
  remaining location in the same transaction.
- Moving a location deletes its `travel_times` rows: the PK is unchanged, so the cascade
  that would otherwise invalidate them never fires.
- A violation of a named constraint becomes a `LocationConflictError` with a message the app
  can show. `get_session` never commits, so each write commits here.
"""

from typing import Any
from uuid import UUID

from sqlalchemy import Select, delete, func, insert, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.models import CreateSavedLocation, SavedLocation, UpdateSavedLocation
from app.db import models as db

CONFLICT_MESSAGES: dict[str, str] = {
    "saved_locations_label_unique": "You already have a place with that label",
    "saved_locations_one_home_idx": "You already have a home",
    "saved_locations_one_work_idx": "You already have a work place",
    "saved_locations_kind_valid": "Kind must be home, work or other",
}

LAST_LOCATION_MESSAGE = "You can't delete your only place"

# `UpdateSavedLocation` fields that are NOT NULL in the table: an explicit null means "leave it".
_REQUIRED_FIELDS = frozenset({"label", "kind", "latitude", "longitude"})

_COLUMNS = (
    db.SavedLocation.id,
    db.SavedLocation.label,
    db.SavedLocation.address,
    db.SavedLocation.latitude,
    db.SavedLocation.longitude,
    db.SavedLocation.is_default,
    db.SavedLocation.kind,
)


class LocationNotFoundError(Exception):
    """No location with that id belongs to the user."""


class LastLocationError(Exception):
    """The user's only location can't be deleted: at least one is required."""


class LocationConflictError(Exception):
    """A write violated one of the constraints in `CONFLICT_MESSAGES`."""

    def __init__(self, constraint: str) -> None:
        self.constraint = constraint
        self.detail = CONFLICT_MESSAGES[constraint]
        super().__init__(self.detail)


def _constraint_name(error: IntegrityError) -> str | None:
    """The violated constraint's name, as asyncpg reports it.

    SQLAlchemy's asyncpg adapter wraps asyncpg's exception in its own DBAPI error and raises
    that `from` the original, so `constraint_name` is on `orig.__cause__`.
    """

    for candidate in (error.orig, getattr(error.orig, "__cause__", None)):
        name = getattr(candidate, "constraint_name", None)
        if isinstance(name, str):
            return name
    return None


async def _conflict_or_raise(session: AsyncSession, error: IntegrityError) -> LocationConflictError:
    await session.rollback()
    constraint = _constraint_name(error)
    if constraint not in CONFLICT_MESSAGES:
        raise error
    return LocationConflictError(constraint)


def _owned(user_id: UUID) -> Select[Any]:
    return select(*_COLUMNS).where(db.SavedLocation.user_id == user_id)


def _clear_default(user_id: UUID) -> Any:
    return (
        update(db.SavedLocation)
        .where(db.SavedLocation.user_id == user_id, db.SavedLocation.is_default)
        .values(is_default=False)
        .execution_options(synchronize_session=False)
    )


async def list_locations(session: AsyncSession, *, user_id: UUID) -> list[SavedLocation]:
    """The user's locations in creation order."""

    stmt = _owned(user_id).order_by(db.SavedLocation.created_at, db.SavedLocation.id)
    rows = (await session.execute(stmt)).mappings().all()
    return [SavedLocation.model_validate(dict(row)) for row in rows]


async def get_location(session: AsyncSession, *, user_id: UUID, location_id: UUID) -> SavedLocation:
    """One of the user's locations."""

    stmt = _owned(user_id).where(db.SavedLocation.id == location_id)
    row = (await session.execute(stmt)).mappings().one_or_none()
    if row is None:
        raise LocationNotFoundError(location_id)
    return SavedLocation.model_validate(dict(row))


async def create_location(
    session: AsyncSession, *, user_id: UUID, location: CreateSavedLocation
) -> SavedLocation:
    """Add a location; the first one, or one created with `make_default`, is the default."""

    count_stmt = (
        select(func.count())
        .select_from(db.SavedLocation)
        .where(db.SavedLocation.user_id == user_id)
    )
    is_first = (await session.execute(count_stmt)).scalar_one() == 0
    is_default = is_first or location.make_default

    try:
        if is_default and not is_first:
            await session.execute(_clear_default(user_id))
        stmt = (
            insert(db.SavedLocation)
            .values(
                user_id=user_id,
                label=location.label,
                address=location.address,
                latitude=location.latitude,
                longitude=location.longitude,
                is_default=is_default,
                kind=location.kind.value,
            )
            .returning(*_COLUMNS)
        )
        row = (await session.execute(stmt)).mappings().one()
    except IntegrityError as error:
        raise await _conflict_or_raise(session, error) from error

    await session.commit()
    return SavedLocation.model_validate(dict(row))


async def update_location(
    session: AsyncSession,
    *,
    user_id: UUID,
    location_id: UUID,
    changes: UpdateSavedLocation,
) -> SavedLocation:
    """Change only the supplied fields; `make_default=true` promotes this location."""

    current_stmt = _owned(user_id).where(db.SavedLocation.id == location_id).with_for_update()
    current_row = (await session.execute(current_stmt)).mappings().one_or_none()
    if current_row is None:
        raise LocationNotFoundError(location_id)
    current = SavedLocation.model_validate(dict(current_row))

    supplied = changes.model_dump(mode="json", exclude_unset=True)
    make_default = supplied.pop("make_default", None) is True
    values = {
        field: value
        for field, value in supplied.items()
        if not (value is None and field in _REQUIRED_FIELDS)
    }
    promote = make_default and not current.is_default
    if promote:
        values["is_default"] = True
    if not values:
        return current

    moved = any(
        field in values and values[field] != getattr(current, field)
        for field in ("latitude", "longitude")
    )

    try:
        if promote:
            await session.execute(_clear_default(user_id))
        if moved:
            await session.execute(
                delete(db.TravelTime)
                .where(db.TravelTime.location_id == location_id)
                .execution_options(synchronize_session=False)
            )
        stmt = (
            update(db.SavedLocation)
            .where(db.SavedLocation.id == location_id, db.SavedLocation.user_id == user_id)
            .values(**values)
            .returning(*_COLUMNS)
            .execution_options(synchronize_session=False)
        )
        row = (await session.execute(stmt)).mappings().one()
    except IntegrityError as error:
        raise await _conflict_or_raise(session, error) from error

    await session.commit()
    return SavedLocation.model_validate(dict(row))


async def delete_location(session: AsyncSession, *, user_id: UUID, location_id: UUID) -> None:
    """Delete a location, keeping at least one and exactly one default.

    All of the user's rows are locked first, so two concurrent deletes can't both see a
    second location and leave the user with none.
    """

    stmt = (
        select(db.SavedLocation.id, db.SavedLocation.is_default)
        .where(db.SavedLocation.user_id == user_id)
        .order_by(db.SavedLocation.created_at, db.SavedLocation.id)
        .with_for_update()
    )
    rows = (await session.execute(stmt)).mappings().all()
    target = next((row for row in rows if row["id"] == location_id), None)
    if target is None:
        raise LocationNotFoundError(location_id)
    if len(rows) == 1:
        raise LastLocationError(location_id)

    await session.execute(
        delete(db.SavedLocation)
        .where(db.SavedLocation.id == location_id, db.SavedLocation.user_id == user_id)
        .execution_options(synchronize_session=False)
    )
    if target["is_default"]:
        oldest_remaining = next(row["id"] for row in rows if row["id"] != location_id)
        await session.execute(
            update(db.SavedLocation)
            .where(db.SavedLocation.id == oldest_remaining)
            .values(is_default=True)
            .execution_options(synchronize_session=False)
        )
    await session.commit()
