from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from app.db.session import create_session_factory

SESSION_POOLER_URL = (
    "postgresql+asyncpg://postgres.abcdefgh:pw@aws-0-us-west-1.pooler.supabase.com:5432/postgres"
)


async def test_factory_is_bound_to_an_engine_for_the_given_url() -> None:
    engine, factory = create_session_factory(SESSION_POOLER_URL)

    assert isinstance(engine, AsyncEngine)
    assert engine.url.drivername == "postgresql+asyncpg"
    assert engine.url.port == 5432
    assert isinstance(factory, async_sessionmaker)
    assert factory.kw["bind"] is engine
    assert factory.kw["expire_on_commit"] is False

    # Sessions are cheap to construct and do not connect until a statement runs.
    async with factory() as session:
        assert isinstance(session, AsyncSession)
        assert session.bind is engine

    await engine.dispose()
