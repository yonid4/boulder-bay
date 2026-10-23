import logging
from collections.abc import Sequence
from datetime import UTC, datetime, time
from types import TracebackType
from typing import Any

import pytest
from sqlalchemy.dialects import postgresql

from app.db import models as db
from app.scrape.parse import CrowdReading, NoChartData
from app.scrape.poll import (
    GymResult,
    PollSummary,
    curve_rows,
    load_and_poll,
    load_gyms,
    run_poll,
)
from app.scrape.providers import ProviderUnavailable

LA = "America/Los_Angeles"
# Friday 2026-09-25 09:50 PDT.
NOW = datetime(2026, 9, 25, 16, 50, tzinfo=UTC)
FRIDAY = 5


def gym_row(gym_id: int, slug: str) -> db.Gym:
    return db.Gym(id=gym_id, slug=slug, timezone=LA, google_maps_query=slug)


def hours_row(gym_id: int, day: int, opens: time, closes: time) -> db.GymHours:
    return db.GymHours(gym_id=gym_id, day_of_week=day, opens_at=opens, closes_at=closes)


def reading(**overrides: Any) -> CrowdReading:
    values: dict[str, Any] = {
        "place_name": "Dogpatch Boulders",
        "live_pct": 58,
        "typical_pct": 30,
        # Friday 6 AM-11 PM as Google renders it: 0% before opening and after closing.
        "bars": {(FRIDAY, hour): (0 if hour in (6, 22, 23) else 40) for hour in range(6, 24)}
        | {(0, 12): 25},
    }
    values.update(overrides)
    return CrowdReading(**values)


# Dogpatch's seeded Friday: 07:00-22:00. Sunday 10:00-19:00.
HOURS = [hours_row(1, FRIDAY, time(7), time(22)), hours_row(1, 0, time(10), time(19))]


class FakeProvider:
    """Answers each gym's fetches in order from a script of readings or exceptions."""

    def __init__(self, script: dict[str, list[CrowdReading | Exception]]) -> None:
        self.script = script
        self.calls: list[str] = []

    async def fetch(self, gym: db.Gym, now: datetime) -> CrowdReading:
        self.calls.append(gym.slug)
        outcome = self.script[gym.slug].pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class FakeResult:
    def __init__(self, snapshot_id: int | None) -> None:
        self.snapshot_id = snapshot_id

    def scalar_one_or_none(self) -> int | None:
        return self.snapshot_id


class FakeSession:
    def __init__(self, fail_executes: int = 0, *, snapshot_exists: bool = False) -> None:
        self.statements: list[Any] = []
        self.commits = 0
        self.rollbacks = 0
        self.fail_executes = fail_executes
        # The snapshot insert's RETURNING comes back empty when the tick already has a row.
        self.snapshot_exists = snapshot_exists

    async def execute(self, statement: Any) -> FakeResult:
        if self.fail_executes:
            self.fail_executes -= 1
            raise RuntimeError("connection reset")
        self.statements.append(statement)
        return FakeResult(None if self.snapshot_exists else 1)

    async def commit(self) -> None:
        self.commits += 1

    async def rollback(self) -> None:
        self.rollbacks += 1


def sql(statement: Any) -> str:
    return str(statement.compile(dialect=postgresql.dialect()))


def params(statement: Any) -> dict[str, Any]:
    return dict(statement.compile(dialect=postgresql.dialect()).params)


async def poll(
    session: FakeSession,
    provider: FakeProvider,
    gyms: Sequence[db.Gym],
    *,
    dry_run: bool = False,
) -> PollSummary:
    hours = {gym.id: [hours_row(gym.id, FRIDAY, time(7), time(22))] for gym in gyms}
    return await run_poll(
        session,  # type: ignore[arg-type]
        provider,
        gyms,
        hours,
        now=NOW,
        dry_run=dry_run,
    )


class TestCurveRows:
    def test_drops_bars_for_closed_hours(self) -> None:
        rows = curve_rows(reading(typical_pct=None), HOURS, now=NOW, timezone=LA)

        assert (FRIDAY, 6) not in rows
        assert (FRIDAY, 22) not in rows
        assert rows[(FRIDAY, 7)] == 40
        assert rows[(0, 12)] == 25
        assert len(rows) == 15 + 1

    def test_keeps_a_zero_during_open_hours(self) -> None:
        bars = {(FRIDAY, 12): 0}
        rows = curve_rows(reading(bars=bars, typical_pct=None), HOURS, now=NOW, timezone=LA)

        assert rows == {(FRIDAY, 12): 0}

    def test_fills_the_current_hour_from_typical(self) -> None:
        bars = {slot: pct for slot, pct in reading().bars.items() if slot != (FRIDAY, 9)}
        rows = curve_rows(reading(bars=bars), HOURS, now=NOW, timezone=LA)

        assert rows[(FRIDAY, 9)] == 30

    def test_skips_the_current_hour_fill_when_closed(self) -> None:
        early = datetime(2026, 9, 25, 13, 30, tzinfo=UTC)  # Friday 06:30 PDT
        rows = curve_rows(reading(typical_pct=12), HOURS, now=early, timezone=LA)

        assert (FRIDAY, 6) not in rows


class TestRunPoll:
    async def test_writes_curve_upsert_and_snapshot(self) -> None:
        session = FakeSession()
        provider = FakeProvider({"dogpatch": [reading()]})

        summary = await poll(session, provider, [gym_row(1, "dogpatch")])

        curve, snapshot = session.statements
        assert "ON CONFLICT (gym_id, day_of_week, hour_of_day) DO UPDATE" in sql(curve)
        assert "busy_pct = excluded.busy_pct" in sql(curve)
        written = [key for key in params(curve) if key.startswith("busy_pct")]
        # Friday 07:00-22:00 is 15 hours; the 9 AM one comes from `typical_pct`.
        assert len(written) == 15
        assert "ON CONFLICT ON CONSTRAINT busyness_snapshots_tick_unique DO NOTHING" in sql(
            snapshot
        )
        assert {key: params(snapshot)[key] for key in ("gym_id", "observed_at")} == {
            "gym_id": 1,
            "observed_at": NOW,
        }
        assert (params(snapshot)["live_pct"], params(snapshot)["typical_pct"]) == (58, 30)
        assert session.commits == 1
        assert summary.results[0].curve_rows == 15
        assert summary.results[0].error is None
        assert summary.no_data is False

    async def test_snapshot_insert_returns_its_id(self) -> None:
        session = FakeSession()

        await poll(session, FakeProvider({"dogpatch": [reading()]}), [gym_row(1, "dogpatch")])

        assert "RETURNING busyness_snapshots.id" in sql(session.statements[-1])

    async def test_an_existing_snapshot_is_kept_and_logged(
        self, caplog: pytest.LogCaptureFixture
    ) -> None:
        session = FakeSession(snapshot_exists=True)

        with caplog.at_level(logging.INFO, logger="app"):
            summary = await poll(
                session, FakeProvider({"dogpatch": [reading()]}), [gym_row(1, "dogpatch")]
            )

        assert summary.results[0].error is None
        assert session.commits == 1
        assert any(
            r.levelno == logging.INFO and "dogpatch: a snapshot for" in r.getMessage()
            for r in caplog.records
        )

    async def test_a_new_snapshot_logs_no_duplicate(self, caplog: pytest.LogCaptureFixture) -> None:
        with caplog.at_level(logging.INFO, logger="app"):
            await poll(
                FakeSession(), FakeProvider({"dogpatch": [reading()]}), [gym_row(1, "dogpatch")]
            )

        assert not any("already exists" in r.getMessage() for r in caplog.records)

    async def test_each_successful_gym_logs_its_reading_at_debug(
        self, caplog: pytest.LogCaptureFixture
    ) -> None:
        with caplog.at_level(logging.DEBUG, logger="app"):
            await poll(
                FakeSession(),
                FakeProvider({"dogpatch": [reading()]}),
                [gym_row(1, "dogpatch")],
                dry_run=True,
            )

        (line,) = [r for r in caplog.records if r.levelno == logging.DEBUG]
        assert line.getMessage().startswith("dogpatch: live 58% / usual 30%")
        assert line.getMessage().endswith("(dry run, not written)")

    async def test_snapshot_only_when_no_bar_is_in_open_hours(self) -> None:
        session = FakeSession()
        closed_only = reading(bars={(3, 6): 0}, live_pct=None, typical_pct=None)

        await poll(session, FakeProvider({"dogpatch": [closed_only]}), [gym_row(1, "dogpatch")])

        (snapshot,) = session.statements
        assert "busyness_snapshots" in sql(snapshot)
        assert params(snapshot)["live_pct"] is None

    async def test_one_failing_gym_does_not_stop_the_others(self) -> None:
        session = FakeSession()
        provider = FakeProvider(
            {
                "dogpatch": [NoChartData("stunted"), NoChartData("stunted")],
                "mosaic": [reading()],
            }
        )

        summary = await poll(session, provider, [gym_row(1, "dogpatch"), gym_row(2, "mosaic")])

        dogpatch, mosaic = summary.results
        assert dogpatch.error == "NoChartData: stunted"
        assert mosaic.error is None
        assert session.commits == 1
        assert summary.no_data is False

    async def test_gym_failing_once_is_retried_after_the_first_pass(self) -> None:
        provider = FakeProvider(
            {"dogpatch": [NoChartData("stunted"), reading()], "mosaic": [reading()]}
        )

        summary = await poll(
            FakeSession(), provider, [gym_row(1, "dogpatch"), gym_row(2, "mosaic")]
        )

        assert provider.calls == ["dogpatch", "mosaic", "dogpatch"]
        assert summary.results[0].attempts == 2
        assert summary.results[0].error is None

    async def test_gym_failing_twice_is_tried_exactly_twice(self) -> None:
        provider = FakeProvider({"dogpatch": [NoChartData("a"), NoChartData("b"), reading()]})

        summary = await poll(FakeSession(), provider, [gym_row(1, "dogpatch")])

        assert provider.calls == ["dogpatch", "dogpatch"]
        assert summary.results[0].attempts == 2
        assert summary.results[0].error == "NoChartData: b"

    async def test_gyms_that_succeed_are_never_retried(self) -> None:
        provider = FakeProvider({"dogpatch": [reading()], "mosaic": [reading()]})

        summary = await poll(
            FakeSession(), provider, [gym_row(1, "dogpatch"), gym_row(2, "mosaic")]
        )

        assert provider.calls == ["dogpatch", "mosaic"]
        assert [result.attempts for result in summary.results] == [1, 1]

    async def test_a_failed_write_rolls_back_and_is_retried(self) -> None:
        session = FakeSession(fail_executes=1)
        provider = FakeProvider({"dogpatch": [reading(), reading()]})

        summary = await poll(session, provider, [gym_row(1, "dogpatch")])

        assert session.rollbacks == 1
        assert session.commits == 1
        assert summary.results[0].attempts == 2
        assert summary.results[0].error is None

    async def test_provider_unavailable_stops_the_run(self) -> None:
        provider = FakeProvider({"dogpatch": [ProviderUnavailable("signed out")], "mosaic": []})

        with pytest.raises(ProviderUnavailable):
            await poll(FakeSession(), provider, [gym_row(1, "dogpatch"), gym_row(2, "mosaic")])
        assert provider.calls == ["dogpatch"]

    async def test_dry_run_writes_nothing(self) -> None:
        session = FakeSession()

        summary = await poll(
            session, FakeProvider({"dogpatch": [reading()]}), [gym_row(1, "dogpatch")], dry_run=True
        )

        assert session.statements == []
        assert session.commits == 0
        assert summary.results[0].curve_rows == 15

    async def test_no_bars_anywhere_is_flagged(self) -> None:
        provider = FakeProvider(
            {"dogpatch": [NoChartData("x"), NoChartData("y")], "mosaic": [NoChartData("z")] * 2}
        )

        summary = await poll(
            FakeSession(), provider, [gym_row(1, "dogpatch"), gym_row(2, "mosaic")]
        )

        assert summary.no_data is True
        assert all(result.error for result in summary.results)


class FakeScalars:
    def __init__(self, rows: list[Any]) -> None:
        self.rows = rows

    def all(self) -> list[Any]:
        return self.rows


class FakeReadSession(FakeSession):
    """Answers `load_gyms` with its gyms, then their hours, and records the statements."""

    def __init__(self, gyms: list[db.Gym], hours: list[db.GymHours]) -> None:
        super().__init__()
        self.answers = [gyms, hours]

    async def scalars(self, statement: Any) -> FakeScalars:
        self.statements.append(statement)
        return FakeScalars(self.answers.pop(0))


class TestLoadGyms:
    async def test_groups_hours_by_gym(self) -> None:
        gyms = [gym_row(1, "dogpatch"), gym_row(2, "mosaic")]
        rows = [hours_row(1, FRIDAY, time(7), time(22)), hours_row(2, 0, time(10), time(19))]
        session = FakeReadSession(gyms, rows)

        loaded, hours = await load_gyms(session, [])  # type: ignore[arg-type]

        assert loaded == gyms
        assert hours == {1: [rows[0]], 2: [rows[1]]}
        assert "slug IN" not in sql(session.statements[0])

    async def test_limits_to_the_given_slugs(self) -> None:
        session = FakeReadSession([gym_row(1, "dogpatch")], [])

        await load_gyms(session, ["dogpatch"])  # type: ignore[arg-type]

        assert "slug IN" in sql(session.statements[0])

    async def test_unknown_slug_raises(self) -> None:
        session = FakeReadSession([gym_row(1, "dogpatch")], [])

        with pytest.raises(LookupError, match="mosaic"):
            await load_gyms(session, ["dogpatch", "mosaic"])  # type: ignore[arg-type]


class FakeOpenProvider:
    """A provider that records being opened and closed around its fetches."""

    def __init__(self, provider: FakeProvider) -> None:
        self.provider = provider
        self.opened = 0
        self.closed = 0

    async def __aenter__(self) -> FakeProvider:
        self.opened += 1
        return self.provider

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.closed += 1


class TestLoadAndPoll:
    # NOW is Friday 09:50 local: dogpatch is open 07:00-22:00, mosaic has no Friday row.
    def session(self) -> FakeReadSession:
        gyms = [gym_row(1, "dogpatch"), gym_row(2, "mosaic")]
        rows = [hours_row(1, FRIDAY, time(7), time(22)), hours_row(2, 0, time(10), time(19))]
        return FakeReadSession(gyms, rows)

    async def test_polls_every_loaded_gym_by_default(self) -> None:
        session = self.session()
        provider = FakeProvider({"dogpatch": [reading()], "mosaic": [reading()]})

        summary = await load_and_poll(
            session,  # type: ignore[arg-type]
            lambda: FakeOpenProvider(provider),
            now=NOW,
        )

        assert provider.calls == ["dogpatch", "mosaic"]
        assert [result.slug for result in summary.results] == ["dogpatch", "mosaic"]
        # The read transaction ends before the browser opens, then each gym commits once.
        assert session.commits == 1 + 2

    async def test_open_only_skips_gyms_closed_at_now(self) -> None:
        provider = FakeProvider({"dogpatch": [reading()]})

        summary = await load_and_poll(
            self.session(),  # type: ignore[arg-type]
            lambda: FakeOpenProvider(provider),
            now=NOW,
            open_only=True,
        )

        assert provider.calls == ["dogpatch"]
        assert [result.slug for result in summary.results] == ["dogpatch"]

    async def test_no_open_gym_never_opens_the_provider(self) -> None:
        opened = FakeOpenProvider(FakeProvider({}))
        sunday_night = datetime(2026, 9, 28, 5, 0, tzinfo=UTC)  # Sunday 22:00 PDT

        summary = await load_and_poll(
            self.session(),  # type: ignore[arg-type]
            lambda: opened,
            now=sunday_night,
            open_only=True,
        )

        assert opened.opened == 0
        assert summary.results == []
        assert summary.no_data is False

    async def test_provider_is_closed_after_the_poll(self) -> None:
        opened = FakeOpenProvider(FakeProvider({"dogpatch": [reading()], "mosaic": [reading()]}))

        await load_and_poll(self.session(), lambda: opened, now=NOW)  # type: ignore[arg-type]

        assert (opened.opened, opened.closed) == (1, 1)

    async def test_dry_run_writes_nothing(self) -> None:
        session = self.session()
        provider = FakeProvider({"dogpatch": [reading()], "mosaic": [reading()]})

        await load_and_poll(
            session,  # type: ignore[arg-type]
            lambda: FakeOpenProvider(provider),
            now=NOW,
            dry_run=True,
        )

        assert not any("busyness" in sql(statement) for statement in session.statements[2:])


def test_gym_result_counts_bars() -> None:
    assert GymResult(slug="x").bars == 0
    assert GymResult(slug="x", reading=reading()).bars == 19
