# `supabase/migrations/` — extension layer

Applied with `supabase db push`. State is tracked in
`supabase_migrations.schema_migrations` inside the hosted project.

## What belongs here

Database-level setup that exists *below* the ORM and cannot be expressed as a
SQLAlchemy model:

- extensions (`create extension ... with schema extensions`)
- roles and grants that are not per-table
- anything requiring privileges the application connection doesn't have

## What must never go here

**Application tables.** All ten live in `backend/alembic/versions/`, generated from
`backend/app/db/models.py`. Creating one here would put it outside Alembic's metadata,
and the next `alembic revision --autogenerate` would emit `DROP TABLE` for it.

## Ordering

This runs **before** Alembic. `gyms.geog` and `saved_locations.geog` are
`extensions.geography(Point, 4326)` columns, so PostGIS must already be installed when
the application tables are created.

## Current contents

| migration | what it does |
|---|---|
| `20260907072340_enable_postgis.sql` | installs PostGIS into the `extensions` schema |

PostGIS goes in `extensions`, not `public`, per Supabase convention — which is why every
reference to it in the Alembic migration is schema-qualified. See
`backend/alembic/versions/README.md` for why that matters.
