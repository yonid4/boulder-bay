# Boulder Bay — backend

FastAPI backend, Python >=3.11, dependencies managed with `uv` (`pyproject.toml` + `uv.lock`).

## Run
```
uv run uvicorn app.main:app --reload
```
Serves on localhost:8000; `GET /health` returns `{"status": "ok"}`.

## Checks — run all of these before committing
```
uv run ruff check . && uv run ruff format --check .
uv run mypy app          # strict mode, no exceptions
uv run pytest            # coverage report included via addopts
```
CI (`.github/workflows/ci.yml`) runs exactly these.

## Structure
- `app/main.py` — FastAPI entrypoint. Currently `/health` and a mock `/api/gyms`.
- `app/config.py` — `Settings` (pydantic-settings), read via the cached `get_settings()`. Reads `.env`; see `.env.example`.
- `app/db/base.py` — SQLAlchemy `DeclarativeBase`. All models subclass it and live in the `public` schema.
- `app/db/models.py` — the nine application tables, mirroring `../boulder_bay_schema.sql`.
  `app/db/__init__.py` imports it for its side effect so `Base.metadata` is populated;
  without that import autogenerate sees an empty metadata and proposes dropping everything.
- `alembic/` — async migration environment. `alembic/env.py` pulls the URL from `Settings`, not `alembic.ini`.
- `tests/` — pytest, `asyncio_mode = "auto"`, `pythonpath = ["."]` so `app` imports without installing the package.

## Conventions
- Use `uv add <package>` / `uv add --dev <package>` / `uv sync` — don't hand-edit `uv.lock` or use `pip`.
- Always run Python via `uv run ...`; `.venv/` is gitignored and never assumed active.
- Ruff (line length 100) is both linter and formatter. Mypy is strict — annotate everything.
- Secrets go in `.env` (gitignored). Add every new key to `.env.example` with a comment.

## Database
Postgres is a **hosted Supabase project** — there is no local stack, no Docker, and no
`supabase start`. `DATABASE_URL` and `SUPABASE_URL` are required settings with no
defaults, so a missing `.env` fails immediately instead of silently pointing nowhere.

**Every migration is applied to the real database.** There is no local reset. Read the
autogenerate diff before running `upgrade`, and take a dashboard backup before anything
destructive.

Migrations:
```
uv run alembic revision --autogenerate -m "add gyms table"
uv run alembic upgrade head
```
`alembic/env.py` carries **three** independent guards on autogenerate. Don't remove any:

1. `include_name` restricts it to the `public` schema — without it, autogenerate reflects
   Supabase's own `auth`/`storage`/`realtime` tables and emits `DROP TABLE` for all of them.
2. `SET search_path TO public` on the migration connection. Supabase puts the `extensions`
   schema on the postgres role's search_path, so PostGIS's `spatial_ref_sys` reflects as
   *unqualified* — schema `None`, which `include_name` waves through. Confirmed against the
   real project: without this, the very first autogenerate emits
   `op.drop_table('spatial_ref_sys')` and would break every coordinate transform.
3. `include_object` excludes the two `geog` columns, `gyms_geog_idx`, and the
   `profiles_id_fkey` foreign key. geoalchemy2 renders
   the type unqualified (`geography(Point,4326)`), which cannot resolve under guard 2's
   `search_path`, and Alembic never compares `Computed()` expressions — so autogenerate can
   neither emit these correctly nor detect drift in them. They are hand-written in the
   initial revision instead. Note this filter does **not** apply to columns of a brand-new
   table: Alembic inlines those into `create_table` without consulting the hook, so a
   from-scratch autogenerate still needs the geog columns stripped by hand.
   The FK entry is separate and just as load-bearing: `profiles.id -> auth.users(id)`
   exists in the database but cannot exist on the model, so autogenerate reads it as a
   constraint you deleted and proposes `drop_constraint` — severing profiles from
   Supabase Auth. Verified against the real database.

These are not redundant: (1) filters by schema name, (2) controls what reflection can see
in the first place, (3) filters our own objects. Anything installed into `extensions` is
invisible to autogenerate only because of (2).

After any change to `env.py`, run `alembic revision --autogenerate` and confirm the generated
`upgrade()` body is `pass` before trusting it.

## Gotchas already paid for
- **`env.py` commits by hand and must keep doing so.** `do_run_migrations` runs
  `SET search_path TO public`, which puts the connection in a transaction. Alembic sees
  that (`MigrationContext._in_external_transaction`) and deliberately makes its own
  `begin_transaction()` a no-op, expecting the caller to commit. `connect()` rolls back on
  close, so without the explicit `await connection.commit()` in `run_async_migrations` a
  migration logs `Running upgrade ...`, reports success, and changes nothing. Cost one
  silently discarded migration to find.
- Use the Supavisor **session-mode** pooler (port 5432). The direct connection is
  IPv6-only, and transaction mode (6543) would force `statement_cache_size=0` +
  `NullPool` on asyncpg. `Settings._reject_known_bad_connection_strings` rejects both
  port 6543 and a missing `+asyncpg` driver at startup — leave that validator in place.
- Supabase Auth signs JWTs with **ES256**, verified against `Settings.jwks_url`
  (`{supabase_url}/auth/v1/.well-known/jwks.json`) — not the legacy HS256 shared secret.
- Playwright's sync API blocks; drive it from the async scheduler via
  `asyncio.to_thread` / `run_in_threadpool`.

## Database state
Two revisions are applied to the hosted project: `7bea7599f868` (nine tables,
RLS on with zero policies) and `b00fd69a53b6` (16 gyms, 112 `gym_hours` rows). `alembic
current` should report `b00fd69a53b6`. There is still no `lifespan` engine ownership and no
query layer — nothing reads these tables yet.

## Installed but not yet wired up
These are dependencies and scaffolding only — the features don't exist yet:
- geoalchemy2: used for the `Geography` column type only. Its `alembic_helpers.include_object`
  is deliberately NOT used — it only filters spatial *table names* (`spatial_ref_sys` and
  friends), which guard 2 above already handles.
- APScheduler 3.11: no jobs registered.
- Playwright (+ Chromium installed): no scraper. See `../boulder_bay_plan.md` for the
  `aria-label` parsing contract, including the U+202F narrow no-break space before AM/PM.
- PyJWT: no auth dependency/middleware.
- httpx: no Mapbox Matrix client.
