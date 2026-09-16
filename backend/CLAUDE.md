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
- `app/main.py` — FastAPI entrypoint. Owns `/health` and includes the routers from `app/api/`.
- `app/api/` — Supabase ES256 Bearer-token verification, domain routers, and client-facing
  Pydantic models grouped by domain under `app/api/models/`. The contracts are registered in
  OpenAPI, but every authenticated route still returns `501` until its query/business layer is
  implemented.
- `app/config.py` — `Settings` (pydantic-settings), read via the cached `get_settings()`. Reads `.env`; see `.env.example`.
- `app/db/base.py` — SQLAlchemy `DeclarativeBase`. All models subclass it and live in the `public` schema.
- `app/db/models.py` — the ten application tables. **The DDL source of truth**; the design
  and its rationale are in `../boulder_bay_schema.md`.
  `app/db/__init__.py` imports it for its side effect so `Base.metadata` is populated;
  without that import autogenerate sees an empty metadata and proposes dropping everything.
- `alembic/` — async migration environment. `alembic/env.py` pulls the URL from `Settings`, not `alembic.ini`.
  `alembic/versions/data/logos/` holds the twelve PNGs revision `92a96b89e01d` seeds into
  `gym_logos`; they are read at upgrade time, so deleting them breaks a from-scratch replay.
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
Seven revisions are applied to the hosted project: `7bea7599f868` (the first nine tables,
RLS on with zero policies), `b00fd69a53b6` (16 gyms, 112 `gym_hours` rows),
`502a92ea0636` (revoking anon access to `alembic_version`), `dba1c1f91ed2` (the `gym_logos`
table and `gyms.logo_id`), `92a96b89e01d` (the twelve logo images, 574 KB, and the gym →
mark mapping), `4f8c2d1a9b73` (required, trimmed 1–80 character profile display names), and
`b91e4d2c7a60` (ASCII letter/space display names). `alembic current` should report
`b91e4d2c7a60`. Supabase migrations `20260915160500` and `20260915164000` create profiles
from `auth.users` signup metadata and enforce the same character rule. There is still no
`lifespan` engine ownership and no query layer — **nothing reads these tables yet,
`gym_logos` included**. The typed API contract includes the logo route and `logo_url`, but
serving the bytes and reading every other model remain unimplemented.

## Installed but not yet wired up
These are dependencies and scaffolding only — the features don't exist yet:
- geoalchemy2: used for the `Geography` column type only. Its `alembic_helpers.include_object`
  is deliberately NOT used — it only filters spatial *table names* (`spatial_ref_sys` and
  friends), which guard 2 above already handles.
- APScheduler 3.11: no jobs registered.
- Playwright (+ Chromium installed): no scraper. See `../boulder_bay_plan.md` for the
  `aria-label` parsing contract, including the U+202F narrow no-break space before AM/PM.
- PyJWT: verifies Supabase ES256 access tokens against the project's cached JWKS before protected
  handlers run; the query/business layers remain unimplemented.
- httpx: no Mapbox Matrix client.
