# Boulder Bay

An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

Full plan, stack details, and feature spec live in `boulder_bay_plan.md` — treat it as the source of truth for anything not covered here. The Claude Design mockup (`Boulder Bay.html`) is the source of truth for UI/nav structure where it conflicts with the plan doc (see below).

## v1 scope
- Fixed, curated list of Bay Area bouldering gyms — not general gym discovery.
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

## Subproject context
- `backend/CLAUDE.md` — FastAPI/uv conventions, migrations, and commands.
- `app/` — native SwiftUI iOS app (iOS 17+, `@Observable` MVVM, `URLSession` + `Codable`, Swift Testing). Currently a connectivity-proof placeholder root view; the Map/Rankings/Gyms drawer is not built yet.
- `supabase/` — Supabase CLI config and migrations for the hosted project.

## Repo-wide checks
`README.md` has the full setup and command reference. Before committing, the backend must pass
`ruff check` / `ruff format --check` / `mypy app` / `pytest`, and the app must pass `xcodebuild test`
— these are exactly what `.github/workflows/ci.yml` runs.
