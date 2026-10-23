import logging
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import main
from app.config import get_settings

NEXT_TICK = datetime(2026, 10, 23, 19, 0, tzinfo=UTC)


class FakeEngine:
    def __init__(self) -> None:
        self.disposed = False

    async def dispose(self) -> None:
        self.disposed = True


class FakeSession:
    async def __aenter__(self) -> "FakeSession":
        return self

    async def __aexit__(self, *exc: object) -> None:
        return None

    async def connection(self) -> object:
        return object()

    async def execute(self, statement: Any, params: Any = None) -> None:
        return None

    async def scalar(self, statement: Any) -> None:
        return None


class FakeSessionFactory:
    def __call__(self) -> FakeSession:
        return FakeSession()


class FakeSettings:
    database_url = "postgresql+asyncpg://user:pw@host:5432/postgres"
    scheduler_enabled = False
    health_connect_timeout_seconds = 5.0
    health_lock_timeout_ms = 1000
    health_statement_timeout_ms = 2000
    health_total_timeout_seconds = 8.0
    log_level = "INFO"
    mapbox_token = ""
    supabase_anon_key = "anon"


class FakeScheduler:
    def __init__(self) -> None:
        self.started = False
        self.shutdown_wait: bool | None = None

    def start(self) -> None:
        self.started = True

    def shutdown(self, wait: bool = True) -> None:
        self.shutdown_wait = wait

    def get_jobs(self) -> list[Any]:
        return [SimpleNamespace(next_run_time=NEXT_TICK)]


def test_lifespan_owns_the_engine_and_publishes_the_session_factory(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = FakeEngine()
    factory = FakeSessionFactory()
    seen_urls: list[str] = []

    def fake_create_session_factory(database_url: str) -> tuple[Any, Any]:
        seen_urls.append(database_url)
        return engine, factory

    monkeypatch.setattr(main, "get_settings", lambda: FakeSettings())
    # /health takes its settings through Depends(get_settings), which the patch above misses.
    monkeypatch.setitem(main.app.dependency_overrides, get_settings, FakeSettings)
    monkeypatch.setattr(main, "create_session_factory", fake_create_session_factory)

    with TestClient(main.app) as client:
        assert seen_urls == [FakeSettings.database_url]
        assert client.app.state.session_factory is factory  # type: ignore[attr-defined]
        assert engine.disposed is False
        assert client.get("/health").json() == {
            "status": "ok",
            "last_successful_poll_at": None,
            "poll_state": "known",
            "database": "ok",
        }

    assert engine.disposed is True


def _patch_lifespan(
    monkeypatch: pytest.MonkeyPatch, *, enabled: bool
) -> tuple[FakeEngine, FakeScheduler, list[tuple[Any, Any]]]:
    engine = FakeEngine()
    sched = FakeScheduler()
    created: list[tuple[Any, Any]] = []

    class Settings(FakeSettings):
        scheduler_enabled = enabled

    def fake_create_scheduler(factory: Any, settings: Any) -> FakeScheduler:
        created.append((factory, settings))
        return sched

    monkeypatch.setattr(main, "get_settings", lambda: Settings())
    monkeypatch.setattr(main, "create_session_factory", lambda url: (engine, "factory"))
    monkeypatch.setattr(main, "create_scheduler", fake_create_scheduler)
    return engine, sched, created


def test_lifespan_does_not_start_the_scheduler_when_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _, sched, created = _patch_lifespan(monkeypatch, enabled=False)
    with TestClient(main.app):
        pass
    assert created == []
    assert sched.started is False


def test_lifespan_starts_and_stops_the_scheduler_when_enabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine, sched, created = _patch_lifespan(monkeypatch, enabled=True)
    with TestClient(main.app):
        assert created and created[0][0] == "factory"
        assert sched.started is True
        assert sched.shutdown_wait is None
    assert sched.shutdown_wait is False
    assert engine.disposed is True


def test_configure_logging_adds_a_handler_when_nothing_handles_app_logs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = logging.getLogger()
    monkeypatch.setattr(root, "handlers", [])
    app_logger = logging.getLogger("app")
    monkeypatch.setattr(app_logger, "handlers", [])

    main.configure_logging("DEBUG")
    main.configure_logging("DEBUG")  # a second lifespan run must not add another

    assert app_logger.level == logging.DEBUG
    (handler,) = app_logger.handlers
    assert handler.formatter is not None
    assert handler.formatter._fmt == main.LOG_FORMAT


def test_configure_logging_leaves_handling_to_an_existing_root_handler(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(logging.getLogger(), "handlers", [logging.NullHandler()])
    app_logger = logging.getLogger("app")
    monkeypatch.setattr(app_logger, "handlers", [])

    main.configure_logging("WARNING")

    assert app_logger.level == logging.WARNING
    assert app_logger.handlers == []


@pytest.mark.parametrize(
    ("enabled", "expected"),
    [
        (False, "startup: scheduler off; Mapbox off (straight-line fallback)"),
        (
            True,
            "startup: scheduler on, next tick 2026-10-23T19:00:00+00:00; Realtime ping on; "
            "Mapbox off (straight-line fallback)",
        ),
    ],
)
def test_lifespan_logs_one_startup_line(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    enabled: bool,
    expected: str,
) -> None:
    _patch_lifespan(monkeypatch, enabled=enabled)
    with caplog.at_level(logging.INFO), TestClient(main.app):
        pass
    assert [r.getMessage() for r in caplog.records if r.name == "app.main"] == [expected]


def test_startup_warns_when_the_scheduler_cannot_ping(caplog: pytest.LogCaptureFixture) -> None:
    class Settings(FakeSettings):
        supabase_anon_key = ""
        mapbox_token = "pk.test"

    with caplog.at_level(logging.INFO):
        main.log_startup(Settings(), next_tick=NEXT_TICK)  # type: ignore[arg-type]

    info, warning = caplog.records
    assert info.getMessage().endswith("Realtime ping off; Mapbox on")
    assert warning.levelno == logging.WARNING
    assert "SUPABASE_ANON_KEY" in warning.getMessage()
