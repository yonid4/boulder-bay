from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api import api_router
from app.config import get_settings
from app.db.session import create_session_factory


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Own the database engine for the life of the process."""

    engine, session_factory = create_session_factory(get_settings().database_url)
    app.state.session_factory = session_factory
    try:
        yield
    finally:
        await engine.dispose()


app = FastAPI(title="Boulder Bay", lifespan=lifespan)
app.include_router(api_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
