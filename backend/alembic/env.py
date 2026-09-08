import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context
from app.config import get_settings
from app.db import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# The URL lives in the environment (see `.env.example`), never in alembic.ini.
config.set_main_option("sqlalchemy.url", get_settings().database_url)

target_metadata = Base.metadata

# Supabase owns `auth`, `storage`, `realtime`, etc. in the same database.
# Without this filter, autogenerate reflects them and emits DROP TABLE for
# every one of them. Only `public` is ours.
INCLUDED_SCHEMAS = {"public", None}


def include_name(name: str | None, type_: str, parent_names: dict[str, str | None]) -> bool:
    if type_ == "schema":
        return name in INCLUDED_SCHEMAS
    return True


def run_migrations_offline() -> None:
    """Run migrations without a DBAPI connection, emitting SQL to stdout."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_schemas=False,
        include_name=include_name,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    # Supabase installs extensions into `extensions` and puts that schema on the
    # postgres role's search_path. Reflection then sees PostGIS's own objects
    # (spatial_ref_sys, geometry_columns) as unqualified — i.e. as if they were
    # ours — and autogenerate emits DROP TABLE for them. Verified against the
    # real project: without this line, the first autogenerate drops spatial_ref_sys
    # and takes every coordinate transform with it.
    #
    # `include_name` cannot catch this: these objects report schema None, not
    # "extensions". Pinning the search_path is what actually scopes reflection.
    connection.exec_driver_sql("SET search_path TO public")

    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_schemas=False,
        include_name=include_name,
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
