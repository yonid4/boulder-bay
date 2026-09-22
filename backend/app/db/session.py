"""Async engine and session factory for request-scoped database access.

Built once per process by the FastAPI `lifespan` in `app/main.py` and handed out per
request through `app.api.dependencies.get_session`. Nothing here connects at import
time: SQLAlchemy engines open connections lazily, so importing the app works without
a database (which is what CI does).
"""

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

SessionFactory = async_sessionmaker[AsyncSession]


def create_session_factory(database_url: str) -> tuple[AsyncEngine, SessionFactory]:
    """Create the engine and a session factory bound to it.

    Default pooling is deliberate: the URL points at Supavisor's session-mode pooler
    (see `app/config.py`), which supports asyncpg prepared statements, so neither
    `NullPool` nor `statement_cache_size=0` is needed.
    """

    engine = create_async_engine(database_url)
    return engine, async_sessionmaker(engine, expire_on_commit=False)
