from typing import Any
from uuid import UUID

import pytest
from sqlalchemy.dialects import postgresql

from app.services.memberships import (
    GymNotFoundError,
    add_membership,
    list_membership_slugs,
    remove_membership,
)

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")


def sql(statement: Any) -> str:
    return str(statement.compile(dialect=postgresql.dialect())).lower()


def params(statement: Any) -> set[Any]:
    return set(statement.compile(dialect=postgresql.dialect()).params.values())


class FakeSession:
    """Records statements; `scalar` answers a gym id lookup, `scalars` the slug listing."""

    def __init__(self, *, gym_id: int | None = None, slugs: list[str] | None = None) -> None:
        self.gym_id = gym_id
        self.slugs = slugs or []
        self.scalar_statements: list[Any] = []
        self.scalars_statements: list[Any] = []
        self.executed: list[Any] = []
        self.commits = 0

    async def scalar(self, statement: Any) -> int | None:
        self.scalar_statements.append(statement)
        return self.gym_id

    async def scalars(self, statement: Any) -> Any:
        self.scalars_statements.append(statement)
        slugs = self.slugs

        class Result:
            def all(self) -> list[str]:
                return list(slugs)

        return Result()

    async def execute(self, statement: Any) -> None:
        self.executed.append(statement)

    async def commit(self) -> None:
        self.commits += 1


class TestListMembershipSlugs:
    async def test_returns_slugs_ordered_by_gym_name_for_the_user(self) -> None:
        session = FakeSession(slugs=["dogpatch", "mission-cliffs"])

        slugs = await list_membership_slugs(session, user_id=USER_ID)  # type: ignore[arg-type]

        assert slugs == ["dogpatch", "mission-cliffs"]
        query = sql(session.scalars_statements[0])
        assert "gym_memberships.user_id" in query
        assert "order by gyms.name" in query
        assert USER_ID in params(session.scalars_statements[0])

    async def test_excludes_inactive_gyms(self) -> None:
        session = FakeSession()

        await list_membership_slugs(session, user_id=USER_ID)  # type: ignore[arg-type]

        assert "gyms.is_active" in sql(session.scalars_statements[0])


class TestAddMembership:
    async def test_inserts_with_on_conflict_do_nothing_and_commits(self) -> None:
        session = FakeSession(gym_id=7)

        await add_membership(session, user_id=USER_ID, slug="dogpatch")  # type: ignore[arg-type]

        assert len(session.executed) == 1
        query = sql(session.executed[0])
        assert "insert into gym_memberships" in query
        assert "on conflict do nothing" in query
        assert params(session.executed[0]) >= {USER_ID, 7}
        assert session.commits == 1

    async def test_unknown_or_inactive_slug_raises_without_writing(self) -> None:
        session = FakeSession(gym_id=None)

        with pytest.raises(GymNotFoundError):
            await add_membership(session, user_id=USER_ID, slug="nope")  # type: ignore[arg-type]

        assert session.executed == []
        assert session.commits == 0

    async def test_slug_lookup_only_matches_active_gyms(self) -> None:
        session = FakeSession(gym_id=7)

        await add_membership(session, user_id=USER_ID, slug="dogpatch")  # type: ignore[arg-type]

        assert "gyms.is_active" in sql(session.scalar_statements[0])


class TestRemoveMembership:
    async def test_deletes_the_users_row_for_that_gym_and_commits(self) -> None:
        session = FakeSession(gym_id=7)

        await remove_membership(session, user_id=USER_ID, slug="dogpatch")  # type: ignore[arg-type]

        assert "delete from gym_memberships" in sql(session.executed[0])
        assert params(session.executed[0]) >= {USER_ID, 7}
        assert session.commits == 1

    async def test_unknown_slug_raises_without_writing(self) -> None:
        session = FakeSession(gym_id=None)

        with pytest.raises(GymNotFoundError):
            await remove_membership(session, user_id=USER_ID, slug="nope")  # type: ignore[arg-type]

        assert session.executed == []
        assert session.commits == 0
