from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import main
from app.config import get_settings


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


class FakeScheduler:
    def __init__(self) -> None:
        self.started = False
        self.shutdown_wait: bool | None = None

    def start(self) -> None:
        self.started = True

    def shutdown(self, wait: bool = True) -> None:
        self.shutdown_wait = wait


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
