# `backend/alembic/versions/` — application tables

Applied with `alembic upgrade head` from `backend/`. State is tracked in
`public.alembic_version`. Runs **after** `supabase db push` — see
`../../../supabase/migrations/README.md`.

## What belongs here

The ten application tables, their constraints and indexes, and the reference-data seeds —
the sixteen gyms with their hours, and the twelve gym logos. The models in
`backend/app/db/models.py` are the source these are generated from; the design behind them
is `boulder_bay_schema.md` at the repo root.

`data/logos/` holds the twelve PNGs that `92a96b89e01d` reads at upgrade time. They are seed
source, not a serving path, and the revision reads them **by filename** — renaming or deleting
one breaks a from-scratch replay. See that directory's own README.

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
   authenticated` on all nine tables it creates. Enabled with zero policies, deliberately:
   the anon key ships in the app bundle, and FastAPI connects as table owner and bypasses
   RLS entirely.

## Every new table needs its own RLS block

The block above covers the nine tables that revision creates, and a table added later does
**not** inherit that posture — Supabase's default privileges grant `anon` and `authenticated`
access to newly created tables in `public`, so a new table is reachable through PostgREST with
the bundled anon key until you revoke it. Autogenerate never emits this. Copy the two lines
into any revision that creates a table, as `dba1c1f91ed2` does for `gym_logos`:

```python
op.execute("alter table public.<table> enable row level security")
op.execute("revoke all on public.<table> from anon, authenticated")
```

Verify with `select * from information_schema.table_privileges where table_name = '<table>'` —
the only grantees should be `postgres` and `service_role`.

## Name every foreign key you create

Autogenerate emits `op.create_foreign_key(None, ...)` paired with
`op.drop_constraint(None, ...)`, and the latter cannot execute — the downgrade fails on a
constraint named `None`. Pass the name Postgres would pick anyway (`<table>_<column>_fkey`),
as `dba1c1f91ed2` does. Test it: `alembic downgrade -1` then `upgrade head`.

Items 1 and 2 are filtered out of autogenerate by `include_object` in `alembic/env.py`,
so they are not re-proposed on every run. That filter does **not** apply to columns of a
brand-new table — Alembic inlines those into `create_table` without consulting the hook —
so a from-scratch regeneration still needs the `geog` columns stripped by hand.

## If `upgrade` fails with "Can't locate revision identified by ..."

`public.alembic_version` is stamped with a revision whose file no longer exists, usually
because a throwaway revision was applied and then deleted. Check what the database thinks
it is on with `uv run alembic current`, then either restore the file or `alembic stamp`
to a revision that does exist. Don't delete a revision file that has been applied.
