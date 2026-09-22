from typing import Any

import pytest
from fastapi.testclient import TestClient

from app import main


class FakeEngine:
    def __init__(self) -> None:
        self.disposed = False

    async def dispose(self) -> None:
        self.disposed = True


class FakeSettings:
    database_url = "postgresql+asyncpg://user:pw@host:5432/postgres"


def test_lifespan_owns_the_engine_and_publishes_the_session_factory(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = FakeEngine()
    factory = object()
    seen_urls: list[str] = []

    def fake_create_session_factory(database_url: str) -> tuple[Any, Any]:
        seen_urls.append(database_url)
        return engine, factory

    monkeypatch.setattr(main, "get_settings", lambda: FakeSettings())
    monkeypatch.setattr(main, "create_session_factory", fake_create_session_factory)

    with TestClient(main.app) as client:
        assert seen_urls == [FakeSettings.database_url]
        assert client.app.state.session_factory is factory  # type: ignore[attr-defined]
        assert engine.disposed is False
        assert client.get("/health").json() == {"status": "ok"}

    assert engine.disposed is True
