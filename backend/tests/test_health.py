import logging
from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.dialects import postgresql
from sqlalchemy.exc import OperationalError

from app.api.dependencies import get_session
from app.main import app


class FakeSession:
    """Answers `scalar()` with a canned value, or raises the given error."""

    def __init__(self, result: datetime | None = None, error: Exception | None = None) -> None:
        self.result = result
        self.error = error
        self.statements: list[Any] = []

    async def scalar(self, statement: Any) -> datetime | None:
        self.statements.append(statement)
        if self.error is not None:
            raise self.error
        return self.result


@pytest.fixture
def use_session() -> Iterator[Any]:
    def install(session: FakeSession) -> FakeSession:
        async def fake_session() -> FakeSession:
            return session

        app.dependency_overrides[get_session] = fake_session
        return session

    try:
        yield install
    finally:
        app.dependency_overrides.clear()


def test_health_reports_the_newest_snapshot_tick(client: TestClient, use_session: Any) -> None:
    session = use_session(FakeSession(datetime(2026, 10, 22, 18, 30, tzinfo=UTC)))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "last_successful_poll_at": "2026-10-22T18:30:00Z",
        "poll_state": "known",
    }
    sql = str(session.statements[0].compile(dialect=postgresql.dialect()))
    assert "max(busyness_snapshots.observed_at)" in sql


def test_health_reports_null_before_any_snapshot(client: TestClient, use_session: Any) -> None:
    use_session(FakeSession(None))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "last_successful_poll_at": None,
        "poll_state": "known",
    }


@pytest.mark.parametrize(
    "error",
    [
        OperationalError("select", {}, Exception("down")),
        ConnectionRefusedError("connection refused"),
    ],
    ids=["sqlalchemy", "connect"],
)
def test_health_is_200_unknown_when_the_database_query_fails(
    client: TestClient, use_session: Any, error: Exception
) -> None:
    use_session(FakeSession(error=error))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "last_successful_poll_at": None,
        "poll_state": "unknown",
    }


def test_httpx_request_log_is_quiet_so_tokens_stay_out_of_logs() -> None:
    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING


def test_openapi_describes_the_health_response(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()

    operation = schema["paths"]["/health"]["get"]
    assert "security" not in operation
    ref = operation["responses"]["200"]["content"]["application/json"]["schema"]["$ref"]
    model = schema["components"]["schemas"][ref.rsplit("/", 1)[-1]]
    assert model["required"] == ["last_successful_poll_at", "poll_state"]
    assert model["properties"]["poll_state"]["enum"] == ["known", "unknown"]
    assert model["properties"]["status"]["const"] == "ok"
    assert model["properties"]["last_successful_poll_at"]["anyOf"] == [
        {"type": "string", "format": "date-time"},
        {"type": "null"},
    ]
