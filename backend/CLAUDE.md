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
`alembic/env.py` carries **two** independent guards on autogenerate. Don't remove either:

1. `include_name` restricts it to the `public` schema — without it, autogenerate reflects
   Supabase's own `auth`/`storage`/`realtime` tables and emits `DROP TABLE` for all of them.
2. `SET search_path TO public` on the migration connection. Supabase puts the `extensions`
   schema on the postgres role's search_path, so PostGIS's `spatial_ref_sys` reflects as
   *unqualified* — schema `None`, which `include_name` waves through. Confirmed against the
   real project: without this, the very first autogenerate emits
   `op.drop_table('spatial_ref_sys')` and would break every coordinate transform.

The two are not redundant: (1) filters by schema name, (2) controls what reflection can see
in the first place. Anything installed into `extensions` is invisible to autogenerate only
because of (2). After any change to `env.py`, run `alembic revision --autogenerate` and
confirm the generated `upgrade()` body is `pass` before trusting it.

## Gotchas already paid for
- Use the Supavisor **session-mode** pooler (port 5432). The direct connection is
  IPv6-only, and transaction mode (6543) would force `statement_cache_size=0` +
  `NullPool` on asyncpg. `Settings._reject_known_bad_connection_strings` rejects both
  port 6543 and a missing `+asyncpg` driver at startup — leave that validator in place.
- Supabase Auth signs JWTs with **ES256**, verified against `Settings.jwks_url`
  (`{supabase_url}/auth/v1/.well-known/jwks.json`) — not the legacy HS256 shared secret.
- Playwright's sync API blocks; drive it from the async scheduler via
  `asyncio.to_thread` / `run_in_threadpool`.

## Installed but not yet wired up
These are dependencies and scaffolding only — the features don't exist yet:
- SQLAlchemy async engine + asyncpg: no models, no `lifespan` engine ownership yet.
- APScheduler 3.11: no jobs registered.
- Playwright (+ Chromium installed): no scraper. See `../boulder_bay_plan.md` for the
  `aria-label` parsing contract, including the U+202F narrow no-break space before AM/PM.
- PyJWT: no auth dependency/middleware.
- httpx: no Mapbox Matrix client.
