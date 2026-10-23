import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated

from fastapi import Depends, FastAPI
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncConnection

from app.api.dependencies import DbSession
from app.api.models import DatabaseState, HealthStatus
from app.api.router import api_router
from app.config import Settings, get_settings
from app.db import models as db
from app.db.session import create_session_factory
from app.scrape.scheduler import create_scheduler

logger = logging.getLogger(__name__)

# httpx logs every request URL at INFO, and Mapbox URLs carry `access_token`. Keep that log
# quiet so an INFO-level run (the scheduler command, for one) never prints the token.
logging.getLogger("httpx").setLevel(logging.WARNING)

# SQLSTATEs that /health reports as a cause rather than a plain "error".
LOCK_NOT_AVAILABLE = "55P03"  # lock_timeout fired
QUERY_CANCELED = "57014"  # statement_timeout fired
TOO_MANY_CONNECTIONS = "53300"
CONNECTION_EXCEPTION_CLASS = "08"  # connection lost or refused by the server


LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s: %(message)s"


def configure_logging(level: str) -> None:
    """Make the app's own `app.*` logs visible at `level`.

    uvicorn configures only `uvicorn.*`, so `app.*` records reach no handler. One goes on the
    `app` logger, but only while nothing handles them already (a root handler from
    `logging.basicConfig`, or pytest's), so no line is ever printed twice.
    """

    app_logger = logging.getLogger("app")
    app_logger.setLevel(level)
    if not app_logger.handlers and not logging.getLogger().handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter(LOG_FORMAT))
        app_logger.addHandler(handler)


def log_startup(settings: Settings, *, next_tick: datetime | None) -> None:
    """One line naming the env-controlled features this process runs with.

    `next_tick` is the scheduler's first run, or None when the scheduler is off.
    """

    mapbox = "on" if settings.mapbox_token else "off (straight-line fallback)"
    if next_tick is None:
        logger.info("startup: scheduler off; Mapbox %s", mapbox)
        return
    ping = "on" if settings.supabase_anon_key else "off"
    logger.info(
        "startup: scheduler on, next tick %s; Realtime ping %s; Mapbox %s",
        next_tick.isoformat(),
        ping,
        mapbox,
    )
    if not settings.supabase_anon_key:
        logger.warning("startup: SUPABASE_ANON_KEY is unset, so polls won't ping open apps")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Own the database engine, and the poll scheduler when enabled, for the process."""

    settings = get_settings()
    configure_logging(settings.log_level)
    engine, session_factory = create_session_factory(settings.database_url)
    app.state.session_factory = session_factory
    scheduler = None
    next_tick = None
    if settings.scheduler_enabled:
        scheduler = create_scheduler(session_factory, settings)
        scheduler.start()
        (job,) = scheduler.get_jobs()
        next_tick = job.next_run_time
    log_startup(settings, next_tick=next_tick)
    try:
        yield
    finally:
        if scheduler is not None:
            scheduler.shutdown(wait=False)
        await engine.dispose()


app = FastAPI(title="Boulder Bay", lifespan=lifespan)
app.include_router(api_router)


def _sqlstate(error: BaseException) -> str | None:
    """asyncpg errors carry `sqlstate`; SQLAlchemy's wrapper copies it onto `.orig`."""

    for candidate in (error, getattr(error, "orig", None)):
        code = getattr(candidate, "sqlstate", None)
        if isinstance(code, str):
            return code
    return None


def classify_database_error(error: BaseException) -> DatabaseState:
    """Name why the database couldn't be read, from the error alone.

    Timeouts and socket errors (refused, DNS, TLS) are all `OSError`s: no connection, or no
    reply, reads as "unreachable". A server-side cancel names its own cause by SQLSTATE.
    """

    code = _sqlstate(error)
    if code == LOCK_NOT_AVAILABLE:
        return "locked"
    if code in (QUERY_CANCELED, TOO_MANY_CONNECTIONS):
        return "overloaded"
    if code is not None and code.startswith(CONNECTION_EXCEPTION_CLASS):
        return "unreachable"
    if isinstance(error, OSError):
        return "unreachable"
    if isinstance(error, DBAPIError) and error.connection_invalidated:
        return "unreachable"
    return "error"


@app.get("/health", response_model=HealthStatus)
async def health(
    session: DbSession, settings: Annotated[Settings, Depends(get_settings)]
) -> HealthStatus:
    """Liveness, plus the newest snapshot's tick so a stalled poller is visible.

    Read from the database rather than the scheduler, so it covers CLI polls too and
    survives a restart. The process being up is what 200 means: if the database can't be
    read in time, answer 200 anyway with `poll_state="unknown"` and the cause in
    `database`. The lock and statement timeouts are `SET LOCAL`, so they end with this
    request's transaction and never reach the pooled connection's next user.
    """

    connection: AsyncConnection | None = None
    try:
        async with asyncio.timeout(settings.health_total_timeout_seconds):
            async with asyncio.timeout(settings.health_connect_timeout_seconds):
                connection = await session.connection()
            await session.execute(
                text(
                    "select set_config('lock_timeout', :lock, true),"
                    " set_config('statement_timeout', :statement, true)"
                ),
                {
                    "lock": f"{settings.health_lock_timeout_ms}ms",
                    "statement": f"{settings.health_statement_timeout_ms}ms",
                },
            )
            latest = await session.scalar(select(func.max(db.BusynessSnapshot.observed_at)))
    except Exception as error:  # /health must answer; every failure is reported, not raised
        state = classify_database_error(error)
        logger.warning("health: database %s: %s: %s", state, type(error).__name__, error)
        if state == "unreachable" and connection is not None:
            # A query cut off mid-flight leaves the connection unusable; don't pool it.
            # Best effort: the check has already failed either way.
            with contextlib.suppress(Exception):
                await connection.invalidate()
        return HealthStatus(last_successful_poll_at=None, poll_state="unknown", database=state)
    return HealthStatus(last_successful_poll_at=latest, poll_state="known", database="ok")
