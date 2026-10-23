from decimal import Decimal
from typing import Any
from uuid import uuid4

import pytest
from sqlalchemy.dialects import postgresql

from app.db import models as db
from app.services.ranking import (
    BASE_SCORE,
    DEFAULT_WEIGHTS,
    RankingWeights,
    get_or_create_ranking_prefs,
    score,
)


class TestScore:
    # The mockup formula: 100 - 0.6 * busy% - 0.5 * min(travel, 60) + 15 if member.
    @pytest.mark.parametrize(
        ("busy_pct", "travel", "member", "expected"),
        [
            (0, 0, False, 100.0),
            (50, 20, False, 60.0),
            (50, 20, True, 75.0),
            (80, 30, False, 37.0),
            (100, 60, False, 10.0),
            (100, 60, True, 25.0),
        ],
    )
    def test_reproduces_mockup_numbers(
        self, busy_pct: float, travel: float, member: bool, expected: float
    ) -> None:
        result = score(busy_pct=busy_pct, is_open=True, travel_minutes=travel, is_member=member)
        assert result == pytest.approx(expected)

    def test_travel_is_capped(self) -> None:
        near_cap = score(busy_pct=0, is_open=True, travel_minutes=60, is_member=False)
        far = score(busy_pct=0, is_open=True, travel_minutes=240, is_member=False)
        assert far == near_cap == pytest.approx(70.0)

    def test_unknown_busyness_counts_as_fifty_when_open(self) -> None:
        unknown = score(busy_pct=None, is_open=True, travel_minutes=10, is_member=False)
        fifty = score(busy_pct=50, is_open=True, travel_minutes=10, is_member=False)
        assert unknown == fifty

    def test_closed_ignores_busyness_and_subtracts_penalty(self) -> None:
        closed = score(busy_pct=90, is_open=False, travel_minutes=20, is_member=False)
        # crowd = 0, so 100 - 0.5 * 20 - 60
        assert closed == pytest.approx(30.0)

    def test_closed_member_keeps_boost(self) -> None:
        closed = score(busy_pct=None, is_open=False, travel_minutes=20, is_member=True)
        assert closed == pytest.approx(45.0)

    def test_custom_weights(self) -> None:
        weights = RankingWeights(
            w_crowd=1.0, w_travel=1.0, member_boost=0.0, closed_penalty=0.0, travel_cap_minutes=10
        )
        result = score(
            busy_pct=40, is_open=True, travel_minutes=30, is_member=True, weights=weights
        )
        assert result == pytest.approx(BASE_SCORE - 40 - 10)

    def test_defaults_match_schema_defaults(self) -> None:
        assert RankingWeights(0.6, 0.5, 15.0, 60.0, 60) == DEFAULT_WEIGHTS


class TestRankingWeights:
    def test_from_prefs_converts_decimals(self) -> None:
        prefs = db.RankingPrefs(
            user_id=uuid4(),
            w_crowd=Decimal("0.700"),
            w_travel=Decimal("0.400"),
            member_boost=Decimal("12.50"),
            closed_penalty=Decimal("50.00"),
            travel_cap_minutes=45,
        )
        assert RankingWeights.from_prefs(prefs) == RankingWeights(0.7, 0.4, 12.5, 50.0, 45)


class FakeSession:
    def __init__(self, row: db.RankingPrefs) -> None:
        self.row = row
        self.executed: list[Any] = []
        self.scalar_statements: list[Any] = []

    async def execute(self, statement: Any) -> None:
        self.executed.append(statement)

    async def scalars(self, statement: Any) -> Any:
        self.scalar_statements.append(statement)
        row = self.row

        class Result:
            def one(self) -> db.RankingPrefs:
                return row

        return Result()


class TestGetOrCreateRankingPrefs:
    async def test_inserts_with_do_nothing_then_selects(self) -> None:
        user_id = uuid4()
        row = db.RankingPrefs(user_id=user_id)
        session = FakeSession(row)

        result = await get_or_create_ranking_prefs(session, user_id)  # type: ignore[arg-type]

        assert result is row
        assert len(session.executed) == 1
        insert_sql = str(session.executed[0].compile(dialect=postgresql.dialect()))
        assert "INSERT INTO ranking_prefs (user_id)" in insert_sql
        assert "ON CONFLICT DO NOTHING" in insert_sql
        select_sql = str(session.scalar_statements[0].compile(dialect=postgresql.dialect()))
        assert "FROM ranking_prefs" in select_sql
        assert "user_id" in select_sql
