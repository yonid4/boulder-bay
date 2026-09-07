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

## Subproject context
- `backend/CLAUDE.md` — FastAPI/uv conventions and commands.
- `app/` — native SwiftUI iOS app; Xcode project not yet scaffolded (see `boulder_bay_plan.md`).
