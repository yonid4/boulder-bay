import asyncio
import logging
import socket
from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.dialects import postgresql
from sqlalchemy.exc import DBAPIError, OperationalError

from app.api.dependencies import get_session
from app.config import Settings, get_settings
from app.main import app, classify_database_error


class FakeConnection:
    def __init__(self) -> None:
        self.invalidated = False

    async def invalidate(self) -> None:
        self.invalidated = True


class FakeSession:
    """Plays the three steps /health takes: connect, set the timeouts, read the max.

    Each step can be delayed (to trip a timeout) or made to raise.
    """

    def __init__(
        self,
        result: datetime | None = None,
        *,
        connect_error: BaseException | None = None,
        connect_delay: float = 0,
        query_error: BaseException | None = None,
        query_delay: float = 0,
    ) -> None:
        self.result = result
        self.connect_error = connect_error
        self.connect_delay = connect_delay
        self.query_error = query_error
        self.query_delay = query_delay
        self.conn = FakeConnection()
        self.executed: list[tuple[Any, Any]] = []
        self.statements: list[Any] = []

    async def connection(self) -> FakeConnection:
        await asyncio.sleep(self.connect_delay)
        if self.connect_error is not None:
            raise self.connect_error
        return self.conn

    async def execute(self, statement: Any, params: Any = None) -> None:
        self.executed.append((statement, params))

    async def scalar(self, statement: Any) -> datetime | None:
        self.statements.append(statement)
        await asyncio.sleep(self.query_delay)
        if self.query_error is not None:
            raise self.query_error
        return self.result


def make_settings() -> Settings:
    return Settings(
        _env_file=None,  # type: ignore[call-arg]
        database_url="postgresql+asyncpg://user:pw@host:5432/postgres",
        supabase_url="https://example.supabase.co",
        health_connect_timeout_seconds=0.05,
        health_lock_timeout_ms=1000,
        health_statement_timeout_ms=2000,
        health_total_timeout_seconds=0.2,
    )


class PgError(Exception):
    """Stands in for an asyncpg error, which carries its SQLSTATE."""

    def __init__(self, sqlstate: str) -> None:
        super().__init__(f"sqlstate {sqlstate}")
        self.sqlstate = sqlstate


def wrapped(sqlstate: str) -> DBAPIError:
    """What SQLAlchemy raises for a server error: the code is on `.orig`."""

    return DBAPIError("select", {}, PgError(sqlstate))


@pytest.fixture
def use_session() -> Iterator[Any]:
    def install(session: FakeSession) -> FakeSession:
        async def fake_session() -> FakeSession:
            return session

        app.dependency_overrides[get_session] = fake_session
        app.dependency_overrides[get_settings] = make_settings
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
        "database": "ok",
    }
    sql = str(session.statements[0].compile(dialect=postgresql.dialect()))
    assert "max(busyness_snapshots.observed_at)" in sql


def test_health_sets_transaction_local_timeouts_before_the_query(
    client: TestClient, use_session: Any
) -> None:
    session = use_session(FakeSession(None))

    client.get("/health")

    statement, params = session.executed[0]
    assert "set_config('lock_timeout', :lock, true)" in str(statement)
    assert "set_config('statement_timeout', :statement, true)" in str(statement)
    assert params == {"lock": "1000ms", "statement": "2000ms"}


def test_health_reports_null_before_any_snapshot(client: TestClient, use_session: Any) -> None:
    use_session(FakeSession(None))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "last_successful_poll_at": None,
        "poll_state": "known",
        "database": "ok",
    }


@pytest.mark.parametrize(
    ("session", "database"),
    [
        (FakeSession(connect_error=ConnectionRefusedError("refused")), "unreachable"),
        (FakeSession(connect_error=socket.gaierror("no such host")), "unreachable"),
        (FakeSession(connect_delay=1), "unreachable"),
        (FakeSession(connect_error=PgError("53300")), "overloaded"),
        (FakeSession(query_error=wrapped("55P03")), "locked"),
        (FakeSession(query_error=wrapped("57014")), "overloaded"),
        (FakeSession(query_error=wrapped("08006")), "unreachable"),
        (FakeSession(query_delay=1), "unreachable"),
        (FakeSession(connect_error=PgError("28P01")), "error"),
        (FakeSession(query_error=OperationalError("select", {}, Exception("x"))), "error"),
    ],
    ids=[
        "refused",
        "dns",
        "connect-timeout",
        "too-many-connections",
        "lock-timeout",
        "statement-timeout",
        "connection-lost",
        "no-reply",
        "bad-password",
        "other",
    ],
)
def test_health_is_200_and_names_the_database_failure(
    client: TestClient, use_session: Any, session: FakeSession, database: str
) -> None:
    use_session(session)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "last_successful_poll_at": None,
        "poll_state": "unknown",
        "database": database,
    }


def test_health_drops_a_connection_cut_off_mid_query(client: TestClient, use_session: Any) -> None:
    session = use_session(FakeSession(query_delay=1))

    client.get("/health")

    assert session.conn.invalidated is True


def test_health_keeps_a_connection_the_server_cancelled_cleanly(
    client: TestClient, use_session: Any
) -> None:
    session = use_session(FakeSession(query_error=wrapped("55P03")))

    client.get("/health")

    assert session.conn.invalidated is False


def test_a_connection_invalidated_by_sqlalchemy_is_unreachable() -> None:
    error = DBAPIError("select", {}, Exception("gone"), connection_invalidated=True)

    assert classify_database_error(error) == "unreachable"


def test_httpx_request_log_is_quiet_so_tokens_stay_out_of_logs() -> None:
    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING


def test_openapi_describes_the_health_response(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()

    operation = schema["paths"]["/health"]["get"]
    assert "security" not in operation
    ref = operation["responses"]["200"]["content"]["application/json"]["schema"]["$ref"]
    model = schema["components"]["schemas"][ref.rsplit("/", 1)[-1]]
    assert model["required"] == ["last_successful_poll_at", "poll_state", "database"]
    assert model["properties"]["status"]["const"] == "ok"
    assert model["properties"]["poll_state"]["enum"] == ["known", "unknown"]
    assert model["properties"]["database"]["enum"] == [
        "ok",
        "unreachable",
        "overloaded",
        "locked",
        "error",
    ]
    assert model["properties"]["last_successful_poll_at"]["anyOf"] == [
        {"type": "string", "format": "date-time"},
        {"type": "null"},
    ]
