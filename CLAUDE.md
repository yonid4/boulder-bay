# Boulder Bay

An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

Full plan, stack details, and feature spec live in `boulder_bay_plan.md` — treat it as the source of truth for anything not covered here. The Claude Design mockup (`Boulder Bay.html`) is the source of truth for UI/nav structure where it conflicts with the plan doc (see below). For anything about the database, `boulder_bay_schema.md` wins over the plan doc.

## v1 scope
- Fixed, curated list of **16 real Bay Area bouldering gyms** — Touchstone (8), Movement (4), Benchmark (2), independents (2). Not general gym discovery.
- Live busyness per gym, plus a "best time to climb" recommendation based on historical patterns.
- "Best gym for me right now" ranking: distance + crowd level + a membership boost for gyms you belong to.
- A small set of saved locations (home + a couple others) you switch between — no real-time GPS in v1.
- Sign-up + login in-app; not a public release.

## Key decisions locked in
- **Monorepo, not two repos.** `backend/` (FastAPI + `uv`) and `app/` (native SwiftUI, Xcode + SPM) live side by side in this one repo.
- **Nav structure follows the mockup.** v1 nav is a hamburger side-menu with **Map / Rankings / Gyms**, and there is no separate Settings screen. Don't reintroduce bottom tabs or a Settings screen without checking with the user first.
- **The Xcode project is generated.** `app/project.yml` (XcodeGen) is the source of truth; `app/BoulderBay.xcodeproj` is gitignored. Add sources, targets, SPM packages and Info.plist keys to `project.yml`, then run `xcodegen generate`. Never hand-edit the `.xcodeproj`.
- **Supabase is cloud-only.** A hosted project is the one database; there is no local stack and Docker isn't part of the toolchain. `DATABASE_URL` / `SUPABASE_URL` are required settings, and migrations you push hit the real database — there is no local reset to fall back on.
- **Supabase provides Auth only.** FastAPI remains the sole data API; the app never queries PostgREST directly. Sign-up/login go through `supabase-swift`, and FastAPI verifies the resulting ES256 JWT. Don't move CRUD to PostgREST without checking with the user first — it would split the API surface and undercut the backend-focused goal in the plan.
- **Logos live in the database, not the app bundle.** The twelve marks are rows in `gym_logos`, and `gyms.logo_id` records which of the sixteen gyms uses which — four Movement gyms share one mark, two Benchmark gyms share another. The old `Assets.xcassets` imagesets and the `Image("logo-\(slug)")`-else-brand lookup are gone; nothing is cached on device in v1 by choice. The twelve PNGs committed at `backend/alembic/versions/data/logos/` are the seed source read by `92a96b89e01d`, never a serving path — don't re-add them to the app bundle. Nothing serves the bytes yet; that endpoint is deferred until the app's screens exist.
- **The gym list is real, verified data.** The seed migration `b00fd69a53b6` is the single source of truth for the 16 gyms — slugs, verified addresses, peak-rate tiers and city-qualified map queries all live there. Earlier drafts of this repo carried a placeholder gym list; it is gone and must not come back. These 16 are the real Bay Area set. Addresses, websites and waiver links are filled in and hand-verified for all 16; `google_maps_url` is the only column still NULL throughout, deliberately. Don't invent a value for it, or for any field — unverified data here is worse than a NULL, because the detail screen links straight out to it.
- **The schema is live.** `boulder_bay_schema.md` is the design record — reasoning and rejected alternatives, not DDL. What runs is `backend/app/db/models.py` (ten models) and five applied Alembic revisions — `7bea7599f868` (core schema), `b00fd69a53b6` (the sixteen-gym seed), `502a92ea0636` (revoking anon access to `alembic_version`), `dba1c1f91ed2` (the `gym_logos` table and `gyms.logo_id`) and `92a96b89e01d` (the twelve logo images). The hosted database is **at `92a96b89e01d`**: ten tables, RLS on with zero policies, 16 gyms, 112 `gym_hours` rows, 12 logos, and no grants to `anon`/`authenticated` anywhere in `public`. Four parts of the core migration are hand-written because autogenerate cannot emit them (the two `geog` generated columns, `gyms_geog_idx`, the `auth.users` FK, and the RLS block) — read the comments in the revision before changing it.
- **`alembic/env.py` must commit explicitly.** `do_run_migrations` issues `SET search_path`, which leaves the connection in a transaction; Alembic then treats its own `begin_transaction()` as a no-op and hands commit responsibility to `env.py`. Without the `await connection.commit()` in `run_async_migrations`, every migration logs "Running upgrade ..." and is then silently rolled back. Don't remove that line.

## Subproject context
- `backend/CLAUDE.md` — FastAPI/uv conventions, migrations, and commands.
- `app/` — native SwiftUI iOS app (iOS 17+, Swift 6 strict concurrency, `@Observable` MVVM, `URLSession` + `Codable`, Swift Testing). All five mockup screens plus the drawer are built; `app/FOLDER_STRUCTURE.md` is the map of it. Debug builds serve data from the in-app `MockAPIClient` (seed gyms, synthesized busyness) and use real Supabase Auth when `app/Config/Supabase.xcconfig` (gitignored) has keys, mock auth otherwise. The API contract the app targets is the `APIClient` protocol; the backend's placeholder `/api/gyms` does not match it yet.
- `supabase/` — Supabase CLI config and migrations for the hosted project.
- `boulder_bay_schema.md` / `.sql` — agreed database design and its DDL, plus the 16-gym seed.

## Repo-wide checks
`README.md` has the full setup and command reference. Before committing, the backend must pass
`ruff check` / `ruff format --check` / `mypy app` / `pytest`, and the app must pass `xcodebuild test`
— these are exactly what `.github/workflows/ci.yml` runs.
