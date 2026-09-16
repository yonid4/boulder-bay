# `supabase/migrations/` — extension layer

Applied with `supabase db push`. State is tracked in
`supabase_migrations.schema_migrations` inside the hosted project.

## What belongs here

Database-level setup that exists *below* the ORM and cannot be expressed as a
SQLAlchemy model:

- extensions (`create extension ... with schema extensions`)
- roles and grants that are not per-table
- functions and triggers attached to Supabase-owned schemas such as `auth`
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
| `20260915160500_create_profile_on_signup.sql` | creates `public.profiles` rows from new `auth.users` metadata |
| `20260915164000_restrict_profile_display_name_characters.sql` | limits signup display names to ASCII letters and spaces |

PostGIS goes in `extensions`, not `public`, per Supabase convention — which is why every
reference to it in the Alembic migration is schema-qualified. See
`backend/alembic/versions/README.md` for why that matters.

The signup trigger is defined before Alembic creates `public.profiles` during a from-scratch
setup, but its PL/pgSQL body resolves that table when the trigger runs. Complete both migration
steps before enabling signups.
