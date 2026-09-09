# `backend/alembic/versions/` — application tables

Applied with `alembic upgrade head` from `backend/`. State is tracked in
`public.alembic_version`. Runs **after** `supabase db push` — see
`../../../supabase/migrations/README.md`.

## What belongs here

Everything in `boulder_bay_schema.sql`: the nine application tables, their constraints
and indexes, and the sixteen-gym seed. The models in `backend/app/db/models.py` are the
source these are generated from.

## Workflow

```bash
cd backend
uv run alembic revision --autogenerate -m "what changed"
uv run alembic upgrade head --sql     # review: compiles to SQL, connects to nothing
uv run alembic upgrade head           # apply — hits the real database
```

There is no local database and no reset. Review before applying.

## Four things autogenerate cannot produce

`7bea7599f868_create_core_schema.py` is hand-completed below its
`# ### end Alembic commands ###` marker. If you regenerate the initial migration from
scratch you must re-add all four:

1. **The two `geog` generated columns.** geoalchemy2 renders the type unqualified as
   `geography(Point,4326)`, which cannot resolve under the `search_path = public` that
   `alembic/env.py` pins on the connection — PostGIS lives in `extensions`. Alembic also
   never compares `Computed()` expressions, so it cannot verify these afterwards either.
2. **`gyms_geog_idx`**, the GiST index on `gyms.geog`.
3. **`profiles.id → auth.users(id)`.** Autogenerate is restricted to `public`, so it
   cannot see the `auth` schema and emits no foreign key at all.
4. **The RLS block** — `enable row level security` plus `revoke all ... from anon,
   authenticated` on all nine tables. Enabled with zero policies, deliberately: the
   anon key ships in the app bundle, and FastAPI connects as table owner and bypasses
   RLS entirely.

Items 1 and 2 are filtered out of autogenerate by `include_object` in `alembic/env.py`,
so they are not re-proposed on every run. That filter does **not** apply to columns of a
brand-new table — Alembic inlines those into `create_table` without consulting the hook —
so a from-scratch regeneration still needs the `geog` columns stripped by hand.

## If `upgrade` fails with "Can't locate revision identified by ..."

`public.alembic_version` is stamped with a revision whose file no longer exists, usually
because a throwaway revision was applied and then deleted. Check what the database thinks
it is on with `uv run alembic current`, then either restore the file or `alembic stamp`
to a revision that does exist. Don't delete a revision file that has been applied.
