# Boulder Bay — backend

FastAPI backend, Python >=3.11, dependencies managed with `uv` (`pyproject.toml` + `uv.lock`).

## Checks — run all of these before committing
```
uv run ruff check . && uv run ruff format --check .
uv run mypy app          # strict mode, no exceptions
uv run pytest            # coverage report included via addopts
```
CI (`.github/workflows/ci.yml`) runs exactly these.

## Layout traps
- `app/db/__init__.py` imports `models` for its side effect so `Base.metadata` is populated;
  without that import autogenerate sees an empty metadata and proposes dropping everything.
- `alembic/versions/data/logos/` PNGs are read when revision `92a96b89e01d` runs, so deleting
  them breaks a from-scratch replay.
- `create_session_factory` connects lazily, so importing the app needs no database (CI has none).

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
- Playwright's sync API is bound to the thread that started it. `GoogleMapsProvider` owns one
  worker thread and runs every browser call there; `asyncio.to_thread` would hop threads.

## Database state
Eight revisions are applied to the hosted project: `7bea7599f868` (the first nine tables,
RLS on with zero policies), `b00fd69a53b6` (16 gyms, 112 `gym_hours` rows),
`502a92ea0636` (revoking anon access to `alembic_version`), `dba1c1f91ed2` (the `gym_logos`
table and `gyms.logo_id`), `92a96b89e01d` (the twelve logo images, 574 KB, and the gym →
mark mapping), `4f8c2d1a9b73` (required, trimmed 1–80 character profile display names),
`b91e4d2c7a60` (ASCII letter/space display names), and `75ffc45ed87e`
(`saved_locations.kind`, `home`/`work`/`other` defaulting to `other`, checked by
`saved_locations_kind_valid`, plus the partial unique indexes `saved_locations_one_home_idx`
and `saved_locations_one_work_idx`; applied 2026-10-22). `alembic current` should report
`75ffc45ed87e`. Its `upgrade()` matched a read-only autogenerate against the hosted database, apart from the
check constraint, which autogenerate never emits. Supabase migrations `20260915160500` and
`20260915164000` create profiles from `auth.users` signup metadata and enforce the same character rule. There are no grants
to `anon`/`authenticated` anywhere in `public`. Four parts of the core migration are
hand-written because autogenerate cannot emit them (the two `geog` generated columns,
`gyms_geog_idx`, the `auth.users` FK, and the RLS block) — read the comments in the revision
before changing it.

Which routes touch which tables:
- **`GET /health`:** reads `max(busyness_snapshots.observed_at)` for
  `last_successful_poll_at` (null when there are no snapshots). Unauthenticated. If that
  query fails it still answers 200, with `poll_state: "unknown"`, a null time, and the
  cause in `database` (`unreachable` / `overloaded` / `locked` / `error`), classified by
  `classify_database_error` in `app/main.py` from the timeouts in the `HEALTH_*` settings.
- **`GET /api/gyms` and `GET /api/gyms/{slug}`:** read `gyms`, `gym_hours`,
  `busyness_curves`, `busyness_snapshots` and the caller's `gym_memberships` rows (for
  `is_member`). The scraper and the scheduler write `busyness_curves` and
  `busyness_snapshots`.
- **`GET /api/gyms/{slug}/logo`:** reads `gym_logos` through `gyms.logo_id` and serves the
  bytes. `logo_url` on a gym points at this route, or is `null` when the gym has no logo.
- **`GET /api/me`:** reads `profiles`.
- **`/api/me/memberships`:** `GET` reads `gym_memberships` (joined to `gyms`); `POST` and
  `DELETE` write it.
- **`/api/me/locations`:** reads and writes `saved_locations`. A `PATCH` that changes a
  location's latitude or longitude also deletes that location's `travel_times` rows.
- **`GET /api/rankings`:** reads one of the caller's `saved_locations` (by `location_id`, or
  their default), the active `gyms` within `RANKING_RADIUS_METERS` of it (`ST_DWithin` on
  `gyms_geog_idx`), the same busyness tables as the gym list, and the caller's
  `gym_memberships`. It writes `ranking_prefs` (the caller's row, created with the defaults
  on first use) and `travel_times` (missing or stale pairs, from Mapbox or the fallback),
  and commits both together once.

## Dependency notes
- `supabase` (supabase-py) is used only by `app/scrape/notify.py`, for the scheduler's
  `poll_finished` Realtime ping. Each tick connects, waits for the channel join, sends, and
  closes: `subscribe()` returns before the server acknowledges the join, and a message sent
  before then is only buffered. Its `realtime` package caps `websockets` below 16, which
  pulled it down from 17.1 to 15.0.1.
- geoalchemy2's `alembic_helpers.include_object` is deliberately NOT used — it only filters
  spatial *table names* (`spatial_ref_sys` and friends), which guard 2 above already handles.
- The scraper's `aria-label` parsing contract, including the U+202F narrow no-break space
  before AM/PM, is in `../boulder_bay_plan.md`.
