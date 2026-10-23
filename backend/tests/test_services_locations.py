from typing import Any
from uuid import UUID

import asyncpg.exceptions
import pytest
from sqlalchemy.dialects import postgresql
from sqlalchemy.dialects.postgresql.asyncpg import AsyncAdapt_asyncpg_dbapi
from sqlalchemy.exc import IntegrityError

from app.api.models import CreateSavedLocation, LocationKind, SavedLocation, UpdateSavedLocation
from app.services.locations import (
    CONFLICT_MESSAGES,
    LastLocationError,
    LocationConflictError,
    LocationNotFoundError,
    create_location,
    delete_location,
    get_location,
    list_locations,
    update_location,
)

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
HOME_ID = UUID("d16878be-c4bc-462f-8929-c464b6a5efad")
WORK_ID = UUID("5b0f9f4e-7a39-4d0e-9a53-2f7c1f8a6b21")
GYM_ID = UUID("9a1c3e55-0d7b-4e3f-8f6a-1b2c3d4e5f60")


def sql(statement: Any) -> str:
    return str(statement.compile(dialect=postgresql.dialect())).lower()


def params(statement: Any) -> set[Any]:
    return set(statement.compile(dialect=postgresql.dialect()).params.values())


def row(
    location_id: UUID = HOME_ID,
    *,
    label: str = "Home",
    kind: str = "home",
    is_default: bool = True,
    latitude: float = 37.4852,
    longitude: float = -122.2364,
    address: str | None = "Redwood City, CA",
) -> dict[str, Any]:
    return {
        "id": location_id,
        "label": label,
        "address": address,
        "latitude": latitude,
        "longitude": longitude,
        "is_default": is_default,
        "kind": kind,
    }


def integrity_error(constraint: str, *, check: bool = False) -> IntegrityError:
    """Build the error exactly as SQLAlchemy's asyncpg adapter raises it.

    The adapter wraps asyncpg's exception in its own DBAPI `IntegrityError` and raises it
    `from` the original, so `constraint_name` lives on `orig.__cause__`, not on `orig`.
    """

    asyncpg_class = (
        asyncpg.exceptions.CheckViolationError if check else asyncpg.exceptions.UniqueViolationError
    )
    cause = asyncpg_class.new(
        {"n": constraint, "M": "violates constraint", "C": "23514" if check else "23505"}
    )
    orig = AsyncAdapt_asyncpg_dbapi.IntegrityError(f"{type(cause)}: {cause}")
    orig.__cause__ = cause
    return IntegrityError("statement", None, orig)


class FakeResult:
    def __init__(self, rows: list[dict[str, Any]] | None = None, scalar: Any = None) -> None:
        self.rows = rows or []
        self.scalar = scalar

    def mappings(self) -> "FakeResult":
        return self

    def all(self) -> list[dict[str, Any]]:
        return list(self.rows)

    def one(self) -> dict[str, Any]:
        assert len(self.rows) == 1
        return self.rows[0]

    def one_or_none(self) -> dict[str, Any] | None:
        assert len(self.rows) <= 1
        return self.rows[0] if self.rows else None

    def scalar_one(self) -> Any:
        return self.scalar


class FakeSession:
    """Answers each `execute` with the next scripted result, or raises it if it's an error."""

    def __init__(self, *results: FakeResult | Exception) -> None:
        self.results = list(results)
        self.executed: list[Any] = []
        self.commits = 0
        self.rollbacks = 0

    async def execute(self, statement: Any) -> FakeResult:
        self.executed.append(statement)
        result = self.results.pop(0) if self.results else FakeResult()
        if isinstance(result, Exception):
            raise result
        return result

    async def commit(self) -> None:
        self.commits += 1

    async def rollback(self) -> None:
        self.rollbacks += 1


def create_request(**overrides: Any) -> CreateSavedLocation:
    values: dict[str, Any] = {
        "label": "Home",
        "kind": "home",
        "address": "Redwood City, CA",
        "latitude": 37.4852,
        "longitude": -122.2364,
    }
    values.update(overrides)
    return CreateSavedLocation.model_validate(values)


class TestListLocations:
    async def test_returns_the_users_locations_in_creation_order(self) -> None:
        session = FakeSession(
            FakeResult([row(), row(WORK_ID, label="Office", kind="work", is_default=False)])
        )

        locations = await list_locations(session, user_id=USER_ID)  # type: ignore[arg-type]

        assert [location.id for location in locations] == [HOME_ID, WORK_ID]
        assert locations[1].kind is LocationKind.WORK
        query = sql(session.executed[0])
        assert "saved_locations.user_id" in query
        assert "order by saved_locations.created_at" in query
        assert USER_ID in params(session.executed[0])
        assert session.commits == 0


class TestGetLocation:
    async def test_returns_the_location_scoped_to_the_user(self) -> None:
        session = FakeSession(FakeResult([row()]))

        location = await get_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
        )

        assert location == SavedLocation.model_validate(row())
        assert params(session.executed[0]) >= {USER_ID, HOME_ID}

    async def test_missing_or_another_users_location_raises_not_found(self) -> None:
        session = FakeSession(FakeResult([]))

        with pytest.raises(LocationNotFoundError):
            await get_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location_id=HOME_ID,
            )


class TestCreateLocation:
    async def test_first_location_becomes_default_whatever_its_kind(self) -> None:
        session = FakeSession(FakeResult(scalar=0), FakeResult([row(kind="other", label="Ryan's")]))

        await create_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location=create_request(label="Ryan's", kind="other"),
        )

        assert len(session.executed) == 2
        insert = session.executed[1]
        assert "insert into saved_locations" in sql(insert)
        assert insert.compile(dialect=postgresql.dialect()).params["is_default"] is True
        assert session.commits == 1

    async def test_later_location_is_not_default_and_leaves_the_current_one_alone(self) -> None:
        session = FakeSession(
            FakeResult(scalar=1),
            FakeResult([row(WORK_ID, label="Office", kind="work", is_default=False)]),
        )

        created = await create_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location=create_request(label="Office", kind="work"),
        )

        assert created.id == WORK_ID
        assert len(session.executed) == 2
        insert = session.executed[1]
        compiled = insert.compile(dialect=postgresql.dialect())
        assert compiled.params["is_default"] is False
        assert compiled.params["kind"] == "work"
        assert compiled.params["user_id"] == USER_ID
        assert session.commits == 1

    async def test_make_default_clears_the_old_default_before_inserting(self) -> None:
        session = FakeSession(
            FakeResult(scalar=2),
            FakeResult(),
            FakeResult([row(WORK_ID, label="Office", kind="work", is_default=True)]),
        )

        await create_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location=create_request(label="Office", kind="work", make_default=True),
        )

        clear, insert = session.executed[1], session.executed[2]
        assert sql(clear).startswith("update saved_locations set is_default")
        assert "saved_locations.is_default" in sql(clear)
        assert params(clear) >= {USER_ID, False}
        assert "insert into saved_locations" in sql(insert)
        assert insert.compile(dialect=postgresql.dialect()).params["is_default"] is True
        assert session.commits == 1

    async def test_has_no_count_cap(self) -> None:
        session = FakeSession(
            FakeResult(scalar=40), FakeResult([row(WORK_ID, kind="other", is_default=False)])
        )

        await create_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location=create_request(kind="other"),
        )

        assert session.commits == 1

    @pytest.mark.parametrize(
        ("constraint", "check"),
        [
            ("saved_locations_label_unique", False),
            ("saved_locations_one_home_idx", False),
            ("saved_locations_one_work_idx", False),
            ("saved_locations_kind_valid", True),
            ("saved_locations_one_default_idx", False),
        ],
    )
    async def test_known_constraint_violation_is_a_conflict_with_its_message(
        self, constraint: str, check: bool
    ) -> None:
        session = FakeSession(FakeResult(scalar=1), integrity_error(constraint, check=check))

        with pytest.raises(LocationConflictError) as raised:
            await create_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location=create_request(),
            )

        assert raised.value.constraint == constraint
        assert raised.value.detail == CONFLICT_MESSAGES[constraint]
        assert session.commits == 0
        assert session.rollbacks == 1

    async def test_unknown_integrity_error_propagates(self) -> None:
        session = FakeSession(FakeResult(scalar=1), integrity_error("saved_locations_user_id_fkey"))

        with pytest.raises(IntegrityError):
            await create_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location=create_request(),
            )

        assert session.commits == 0
        assert session.rollbacks == 1


def test_each_conflict_message_is_distinct_and_covers_every_mapped_constraint() -> None:
    assert set(CONFLICT_MESSAGES) == {
        "saved_locations_label_unique",
        "saved_locations_one_home_idx",
        "saved_locations_one_work_idx",
        "saved_locations_kind_valid",
        "saved_locations_one_default_idx",
    }
    assert len(set(CONFLICT_MESSAGES.values())) == len(CONFLICT_MESSAGES)


class TestUpdateLocation:
    async def test_missing_location_raises_not_found_without_writing(self) -> None:
        session = FakeSession(FakeResult([]))

        with pytest.raises(LocationNotFoundError):
            await update_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location_id=HOME_ID,
                changes=UpdateSavedLocation(label="Casa"),
            )

        assert len(session.executed) == 1
        assert session.commits == 0

    async def test_only_supplied_fields_change(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult([row(label="Casa")]))

        updated = await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(label="Casa"),
        )

        assert updated.label == "Casa"
        update = session.executed[1]
        query = sql(update)
        assert query.startswith("update saved_locations set label=")
        assert "address" not in query.split(" where ")[0]
        assert params(update) >= {"Casa", HOME_ID, USER_ID}
        assert session.commits == 1

    async def test_explicit_null_address_clears_it(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult([row(address=None)]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation.model_validate({"address": None}),
        )

        compiled = session.executed[1].compile(dialect=postgresql.dialect())
        assert "address" in compiled.params
        assert compiled.params["address"] is None

    async def test_explicit_null_on_required_fields_is_ignored(self) -> None:
        session = FakeSession(FakeResult([row()]))

        updated = await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation.model_validate(
                {"label": None, "kind": None, "latitude": None, "make_default": None}
            ),
        )

        assert updated == SavedLocation.model_validate(row())
        assert len(session.executed) == 1
        assert session.commits == 0

    async def test_kind_change_is_written_as_text(self) -> None:
        session = FakeSession(FakeResult([row(kind="other")]), FakeResult([row(kind="work")]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(kind=LocationKind.WORK),
        )

        assert session.executed[1].compile(dialect=postgresql.dialect()).params["kind"] == "work"

    async def test_coordinate_change_clears_that_locations_travel_times(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult(), FakeResult([row(latitude=37.5)]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(latitude=37.5),
        )

        statements = [sql(statement) for statement in session.executed]
        clear = next(
            statement
            for statement in session.executed
            if "delete from travel_times" in sql(statement)
        )
        assert "travel_times.location_id" in sql(clear)
        assert params(clear) == {HOME_ID}
        assert any(statement.startswith("update saved_locations") for statement in statements)
        assert session.commits == 1

    async def test_longitude_change_alone_also_clears_travel_times(self) -> None:
        session = FakeSession(
            FakeResult([row()]), FakeResult(), FakeResult([row(longitude=-122.3)])
        )

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(longitude=-122.3),
        )

        assert any("delete from travel_times" in sql(s) for s in session.executed)

    async def test_unchanged_coordinates_keep_travel_times(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult([row(label="Casa")]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(label="Casa", latitude=37.4852, longitude=-122.2364),
        )

        assert not any("travel_times" in sql(s) for s in session.executed)

    async def test_label_only_change_keeps_travel_times(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult([row(label="Casa")]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(label="Casa"),
        )

        assert not any("travel_times" in sql(s) for s in session.executed)

    async def test_promote_clears_the_old_default_then_sets_this_one(self) -> None:
        session = FakeSession(
            FakeResult([row(WORK_ID, label="Office", kind="work", is_default=False)]),
            FakeResult(),
            FakeResult([row(WORK_ID, label="Office", kind="work", is_default=True)]),
        )

        updated = await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=WORK_ID,
            changes=UpdateSavedLocation(make_default=True),
        )

        assert updated.is_default
        clear, promote = session.executed[1], session.executed[2]
        assert sql(clear).startswith("update saved_locations set is_default")
        assert params(clear) >= {USER_ID, False}
        assert WORK_ID not in params(clear)
        assert sql(promote).startswith("update saved_locations set is_default")
        compiled = promote.compile(dialect=postgresql.dialect())
        assert compiled.params["is_default"] is True
        assert params(promote) >= {WORK_ID, USER_ID}
        assert session.commits == 1

    async def test_promoting_the_current_default_is_a_no_op(self) -> None:
        session = FakeSession(FakeResult([row()]))

        updated = await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(make_default=True),
        )

        assert updated.is_default
        assert len(session.executed) == 1
        assert session.commits == 0

    async def test_make_default_false_does_not_demote(self) -> None:
        session = FakeSession(FakeResult([row()]))

        updated = await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(make_default=False),
        )

        assert updated.is_default
        assert len(session.executed) == 1

    async def test_the_current_row_is_locked_and_scoped_to_the_user(self) -> None:
        session = FakeSession(FakeResult([row()]), FakeResult([row(label="Casa")]))

        await update_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
            changes=UpdateSavedLocation(label="Casa"),
        )

        read = session.executed[0]
        assert "for update" in sql(read)
        assert params(read) >= {HOME_ID, USER_ID}

    @pytest.mark.parametrize(
        ("constraint", "check"),
        [
            ("saved_locations_label_unique", False),
            ("saved_locations_one_home_idx", False),
            ("saved_locations_one_work_idx", False),
            ("saved_locations_kind_valid", True),
            ("saved_locations_one_default_idx", False),
        ],
    )
    async def test_known_constraint_violation_is_a_conflict(
        self, constraint: str, check: bool
    ) -> None:
        session = FakeSession(
            FakeResult([row(kind="other")]), integrity_error(constraint, check=check)
        )

        with pytest.raises(LocationConflictError) as raised:
            await update_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location_id=HOME_ID,
                changes=UpdateSavedLocation(kind=LocationKind.HOME),
            )

        assert raised.value.detail == CONFLICT_MESSAGES[constraint]
        assert session.commits == 0
        assert session.rollbacks == 1


class TestDeleteLocation:
    async def test_the_only_location_cannot_be_deleted(self) -> None:
        session = FakeSession(FakeResult([{"id": HOME_ID, "is_default": True}]))

        with pytest.raises(LastLocationError):
            await delete_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location_id=HOME_ID,
            )

        assert len(session.executed) == 1
        assert session.commits == 0

    async def test_missing_or_another_users_location_raises_not_found(self) -> None:
        session = FakeSession(FakeResult([{"id": HOME_ID, "is_default": True}]))

        with pytest.raises(LocationNotFoundError):
            await delete_location(
                session,  # type: ignore[arg-type]
                user_id=USER_ID,
                location_id=GYM_ID,
            )

        assert len(session.executed) == 1
        assert session.commits == 0

    async def test_reads_the_users_rows_oldest_first_and_locks_them(self) -> None:
        session = FakeSession(
            FakeResult([{"id": HOME_ID, "is_default": True}, {"id": WORK_ID, "is_default": False}])
        )

        await delete_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=WORK_ID,
        )

        read = sql(session.executed[0])
        assert "order by saved_locations.created_at" in read
        assert "for update" in read
        assert USER_ID in params(session.executed[0])

    async def test_deleting_a_non_default_location_leaves_the_default_alone(self) -> None:
        session = FakeSession(
            FakeResult([{"id": HOME_ID, "is_default": True}, {"id": WORK_ID, "is_default": False}])
        )

        await delete_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=WORK_ID,
        )

        assert len(session.executed) == 2
        delete = session.executed[1]
        assert "delete from saved_locations" in sql(delete)
        assert params(delete) >= {WORK_ID, USER_ID}
        assert session.commits == 1

    async def test_deleting_the_default_promotes_the_oldest_remaining(self) -> None:
        session = FakeSession(
            FakeResult(
                [
                    {"id": WORK_ID, "is_default": False},
                    {"id": HOME_ID, "is_default": True},
                    {"id": GYM_ID, "is_default": False},
                ]
            )
        )

        await delete_location(
            session,  # type: ignore[arg-type]
            user_id=USER_ID,
            location_id=HOME_ID,
        )

        assert len(session.executed) == 3
        delete, promote = session.executed[1], session.executed[2]
        assert "delete from saved_locations" in sql(delete)
        assert params(delete) >= {HOME_ID}
        assert sql(promote).startswith("update saved_locations set is_default")
        assert promote.compile(dialect=postgresql.dialect()).params["is_default"] is True
        assert WORK_ID in params(promote)
        assert GYM_ID not in params(promote)
        assert session.commits == 1
