import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError

from app.api.dependencies import DbSession
from app.api.models import HealthStatus
from app.api.router import api_router
from app.config import get_settings
from app.db import models as db
from app.db.session import create_session_factory
from app.scrape.scheduler import create_scheduler

logger = logging.getLogger(__name__)

# httpx logs every request URL at INFO, and Mapbox URLs carry `access_token`. Keep that log
# quiet so an INFO-level run (the scheduler command, for one) never prints the token.
logging.getLogger("httpx").setLevel(logging.WARNING)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Own the database engine, and the poll scheduler when enabled, for the process."""

    settings = get_settings()
    engine, session_factory = create_session_factory(settings.database_url)
    app.state.session_factory = session_factory
    scheduler = None
    if settings.scheduler_enabled:
        scheduler = create_scheduler(session_factory, settings)
        scheduler.start()
    try:
        yield
    finally:
        if scheduler is not None:
            scheduler.shutdown(wait=False)
        await engine.dispose()


app = FastAPI(title="Boulder Bay", lifespan=lifespan)
app.include_router(api_router)


@app.get("/health", response_model=HealthStatus)
async def health(session: DbSession) -> HealthStatus:
    """Liveness, plus the newest snapshot's tick so a stalled poller is visible.

    Read from the database rather than the scheduler, so it covers CLI polls too and
    survives a restart. If the database can't be read, the process is still up: answer 200
    with `poll_state="unknown"` rather than failing the liveness check.
    """

    try:
        latest = await session.scalar(select(func.max(db.BusynessSnapshot.observed_at)))
    except (SQLAlchemyError, OSError) as error:
        logger.warning("health: couldn't read the latest snapshot: %s", error)
        return HealthStatus(last_successful_poll_at=None, poll_state="unknown")
    return HealthStatus(last_successful_poll_at=latest, poll_state="known")
