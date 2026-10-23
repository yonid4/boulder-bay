from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.router import api_router
from app.config import get_settings
from app.db.session import create_session_factory
from app.scrape.scheduler import create_scheduler


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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
