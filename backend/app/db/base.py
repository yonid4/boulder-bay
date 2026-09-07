"""Declarative base for all ORM models.

Everything lives in the `public` schema — Alembic autogenerate is restricted to
it in `alembic/env.py`, so Supabase's own `auth`/`storage` tables are never
reflected (and never dropped).
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
