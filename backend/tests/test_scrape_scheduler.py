import logging
from datetime import UTC, datetime
from typing import Any

import pytest

from app.scrape import scheduler
from app.scrape.poll import GymResult, PollSummary
from app.scrape.providers import ProviderUnavailable


@pytest.mark.parametrize(
    ("now", "expected"),
    [
        (datetime(2026, 10, 22, 17, 0, 0, tzinfo=UTC), datetime(2026, 10, 22, 17, 0, tzinfo=UTC)),
        (
            datetime(2026, 10, 22, 17, 0, 4, 500, tzinfo=UTC),
            datetime(2026, 10, 22, 17, 0, tzinfo=UTC),
        ),
        (datetime(2026, 10, 22, 17, 29, 59, tzinfo=UTC), datetime(2026, 10, 22, 17, 0, tzinfo=UTC)),
        (datetime(2026, 10, 22, 17, 30, 1, tzinfo=UTC), datetime(2026, 10, 22, 17, 30, tzinfo=UTC)),
        (
            datetime(2026, 10, 22, 23, 59, 59, tzinfo=UTC),
            datetime(2026, 10, 22, 23, 30, tzinfo=UTC),
        ),
    ],
)
def test_truncate_to_tick(now: datetime, expected: datetime) -> None:
    assert scheduler.truncate_to_tick(now) == expected


class FakeSession:
    pass


class FakeSessionFactory:
    def __init__(self) -> None:
        self.session = FakeSession()
        self.entered = 0

    def __call__(self) -> "FakeSessionFactory":
        return self

    async def __aenter__(self) -> FakeSession:
        self.entered += 1
        return self.session

    async def __aexit__(self, *exc: object) -> None:
        return None


class FakeSettings:
    scrape_profile_dir = "/profile"
    scrape_max_attempts = 3


def install_load_and_poll(monkeypatch: pytest.MonkeyPatch, outcome: object) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []

    async def fake_load_and_poll(session: object, open_provider: object, **kwargs: Any) -> Any:
        calls.append({"session": session, "open_provider": open_provider, **kwargs})
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome

    monkeypatch.setattr(scheduler, "load_and_poll", fake_load_and_poll)
    return calls


async def test_poll_tick_polls_open_gyms_at_the_truncated_tick(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = install_load_and_poll(monkeypatch, PollSummary([]))
    factory = FakeSessionFactory()

    await scheduler.poll_tick(
        factory,
        FakeSettings(),
        now=datetime(2026, 10, 22, 17, 31, 12, tzinfo=UTC),  # type: ignore[arg-type]
    )

    assert len(calls) == 1
    assert calls[0]["session"] is factory.session
    assert calls[0]["now"] == datetime(2026, 10, 22, 17, 30, tzinfo=UTC)
    assert calls[0]["open_only"] is True
    assert "dry_run" not in calls[0] or calls[0]["dry_run"] is False


async def test_poll_tick_builds_a_google_maps_provider_factory(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = install_load_and_poll(monkeypatch, PollSummary([]))
    built: list[tuple[object, int]] = []

    def fake_provider(profile_dir: object, *, max_attempts: int) -> Any:
        built.append((profile_dir, max_attempts))
        return "provider"

    monkeypatch.setattr(scheduler, "GoogleMapsProvider", fake_provider)
    await scheduler.poll_tick(FakeSessionFactory(), FakeSettings())  # type: ignore[arg-type]

    assert calls[0]["open_provider"]() == "provider"
    assert built == [("/profile", 3)]


@pytest.mark.parametrize("error", [ProviderUnavailable("signed out"), LookupError("nope")])
async def test_poll_tick_swallows_expected_errors_and_logs_error(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture, error: Exception
) -> None:
    install_load_and_poll(monkeypatch, error)
    with caplog.at_level(logging.DEBUG):
        await scheduler.poll_tick(FakeSessionFactory(), FakeSettings())  # type: ignore[arg-type]
    assert any(r.levelno == logging.ERROR for r in caplog.records)


async def test_poll_tick_swallows_unexpected_errors(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    install_load_and_poll(monkeypatch, RuntimeError("db down"))
    await scheduler.poll_tick(FakeSessionFactory(), FakeSettings())  # type: ignore[arg-type]
    assert any(r.levelno == logging.ERROR for r in caplog.records)


async def test_poll_tick_logs_error_when_no_gym_returned_data(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    install_load_and_poll(monkeypatch, PollSummary([GymResult(slug="a")]))
    await scheduler.poll_tick(FakeSessionFactory(), FakeSettings())  # type: ignore[arg-type]
    assert any(
        r.levelno == logging.ERROR and "Popular times" in r.getMessage() for r in caplog.records
    )


async def test_poll_tick_does_not_log_error_for_an_empty_tick(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    install_load_and_poll(monkeypatch, PollSummary([]))
    with caplog.at_level(logging.DEBUG):
        await scheduler.poll_tick(FakeSessionFactory(), FakeSettings())  # type: ignore[arg-type]
    assert not [r for r in caplog.records if r.levelno >= logging.WARNING]


def test_create_scheduler_registers_one_half_hourly_job() -> None:
    factory = FakeSessionFactory()
    settings = FakeSettings()
    sched = scheduler.create_scheduler(factory, settings)  # type: ignore[arg-type]

    (job,) = sched.get_jobs()
    assert job.func is scheduler.poll_tick
    assert job.args == (factory, settings)
    assert job.max_instances == 1
    assert job.coalesce is True
    assert job.misfire_grace_time == 300
    fields = {field.name: str(field) for field in job.trigger.fields}
    assert fields["minute"] == "0,30"
    assert str(job.trigger.timezone) == "UTC"
