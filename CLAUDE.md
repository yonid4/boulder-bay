# Boulder Bay

An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

Full plan, stack details, and feature spec live in `boulder_bay_plan.md` — treat it as the source of truth for anything not covered here. The Claude Design mockup (`Boulder Bay.html`) is the source of truth for UI/nav structure where it conflicts with the plan doc (see below). For anything about the database, `boulder_bay_schema.md` wins over the plan doc. The build plan for everything v1 still lacks (rankings, places, memberships, gym detail, logos, the side menu, the scheduler) is `boulder_bay_v1_design.md`; it records where it changes either doc. `boulder_bay_v1_sprints.md` orders that work into sprints; before starting a sprint read its sprint log, and when one finishes, follow its "When a sprint is done" rule (check it off, log what was done and findings for later sprints).

## v1 scope
- Fixed, curated list of **16 real Bay Area bouldering gyms** — Touchstone (8), Movement (4), Benchmark (2), independents (2). Not general gym discovery.
- Live busyness per gym, plus a "best time to climb" recommendation based on historical patterns.
- "Best gym for me right now" ranking: distance + crowd level + a membership boost for gyms you belong to.
- Any number of saved locations, each tagged home / work / other (at most one home and one work, at least one location of any kind), that you switch between — no real-time GPS in v1.
- Sign-up + login in-app; not a public release.

## Key decisions locked in
- **Monorepo, not two repos.** `backend/` (FastAPI + `uv`) and `app/` (native SwiftUI, Xcode + SPM) live side by side in this one repo.
- **Nav structure follows the mockup.** v1 nav is a hamburger side-menu with **Map / Rankings / Gyms**, and there is no separate Settings screen. Don't reintroduce bottom tabs or a Settings screen without checking with the user first.
- **Supabase is cloud-only.** A hosted project is the one database; there is no local stack and Docker isn't part of the toolchain. `DATABASE_URL` / `SUPABASE_URL` are required settings, and migrations you push hit the real database — there is no local reset to fall back on.
- **Supabase provides Auth only.** FastAPI remains the sole data API; the app never queries PostgREST directly. Sign-up/login go through `supabase-swift`, and FastAPI verifies the resulting ES256 JWT. Don't move CRUD to PostgREST without checking with the user first — it would split the API surface and undercut the backend-focused goal in the plan.
- **Logos live in the database, not the app bundle.** The twelve marks are rows in `gym_logos`, and `gyms.logo_id` records which of the sixteen gyms uses which — four Movement gyms share one mark, two Benchmark gyms share another. The old `Assets.xcassets` imagesets and the `Image("logo-\(slug)")`-else-brand lookup are gone; nothing is cached on device in v1 by choice. The twelve PNGs committed at `backend/alembic/versions/data/logos/` are the seed source read by `92a96b89e01d`, never a serving path — don't re-add them to the app bundle. `GET /api/gyms/{slug}/logo` serves the bytes (strong ETag from `gym_logos.sha256`, 304 on `If-None-Match`, `Cache-Control: private, max-age=86400`), and `logo_url` on the gym list points at it.
- **The gym list is real, verified data.** The seed migration `b00fd69a53b6` is the single source of truth for the 16 gyms — slugs, verified addresses, peak-rate tiers and city-qualified map queries all live there. Earlier drafts of this repo carried a placeholder gym list; it is gone and must not come back. These 16 are the real Bay Area set. Addresses, websites and waiver links are filled in and hand-verified for all 16; `google_maps_url` is the only column still NULL throughout, deliberately. Don't invent a value for it, or for any field — unverified data here is worse than a NULL, because the detail screen links straight out to it.
- **The schema is live.** The hosted database is **at `75ffc45ed87e`** (`saved_locations.kind`), the repo head. Revisions, state and migration gotchas are in `backend/CLAUDE.md`. `boulder_bay_schema.md` is the design record — reasoning and rejected alternatives, not DDL.

## Subproject context
- `backend/CLAUDE.md` — FastAPI/uv conventions, migrations, database state, and commands.
- `app/CLAUDE.md` — the generated Xcode project.

## Repo-wide checks
`README.md` has the full setup and command reference. Before committing, the backend must pass
`ruff check` / `ruff format --check` / `mypy app` / `pytest`, and the app must pass `xcodebuild test`
— these are exactly what `.github/workflows/ci.yml` runs.

### Git
Never run `git push` to `main` unless the user explicitly names `main` as the push target. A generic "push the changes" while on `main` is not authorization.

When asked to push while on `main`, stop and ask whether to create a branch (and what to name it) or whether they really mean `main`. Pushing a feature branch is fine when the user asks to push and they are already on that branch.
