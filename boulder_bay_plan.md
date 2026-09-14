# Boulder Bay — Project Plan (v1)

## One-liner
An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

## Motivation
- No Bay Area gym chain (Touchstone, Movement, Benchmark) currently publishes live occupancy on their own site — Google's popular-times data is the only source with coverage across all of them.
- Personal need: decide where to climb, and when, without guessing.
- Resume goal: a backend-flavored personal project (data ingestion, polling, ranking logic) that doesn't lean on an LLM.
- **Skill goal:** Build exclusively in native Swift/SwiftUI as a strong differentiator against an already React/TypeScript-heavy resume.

## Users & Access
- Not a public release for v1.
- Sign-up + login in the UI, so you (and anyone testing with you) can create accounts directly rather than needing manual invites — easier for testing across different areas/gyms beyond just the ones near you.

## Scope for v1
**In scope:**
- Fixed, curated list of 16 Bay Area bouldering gyms — Touchstone (8), Movement (4), Benchmark (2), independents (2). See **Seed data**.
- Live busyness per gym.
- Best time to climb, per gym (based on historical patterns, not just live data).
- "Best gym for me right now" ranking.
- Mark which gyms you're a member of to boost them in the rankings.
- Location input: a set home location plus a couple of other saved spots (e.g. work, a friend's place).

**Out of scope for v1:**
- Real-time GPS/device location (planned for v2).
- Gyms outside the Bay Area / general gym discovery.
- Public sign-up or release.
- Usage-based clustering priority (deferred to v2; clustering priority is membership-only for v1).

## Core Features
1. **Gym list/map view** — see all tracked gyms and where they are.
2. **Live busyness** — current crowd level per gym.
3. **Best time to climb** — a per-gym recommendation based on historical crowd patterns. Defined as the future open hour with the minimum predicted busyness, presented as a one-hour window.
4. **"Best gym right now" ranking** — combines:
   - Distance from your selected location within an acceptable buffer.
   - Current/predicted crowd level (least busy ranks higher).
   - Membership boost (prioritizes gyms where you don't pay a day-rate).
5. **Location switcher** — toggle between home and saved spots to see rankings from each.
6. **Time scrubber** — a slider on the map to move the hour forward and see projected busyness at that time rather than only the current moment.
7. **Gym detail screen** — reached by tapping a gym from the map or Rankings. Shows:
   - Logo and name
   - Address — tappable, opens Apple Maps
   - Hours
   - Busyness — live, plus an hourly forecast for the rest of the day until closing
   - Info such as rates
   - Waiver link, if the gym has one
   - Website link

## UI Structure (v1)
**Hamburger Side-Menu Navigation (No bottom tabs).**
A slide-in drawer handles top-level routing, user profile info, and the sign-out action.

- **Map** — full-screen MapKit map; gym pins show a busyness card when zoomed in, and zoomed-out clusters surface the higher-priority gym(s) (member gyms first, then score). Member gyms carry a dark ring on their pin. Also holds the location switcher, the time scrubber, and a "best right now" affordance.
- **Rankings** — the "best gym right now" list, using the ranking formula.
- **Gyms** — the membership list: search and add/remove the gyms you belong to.

Map and Rankings both push to the same **Gym detail** screen (see Core Features) via `NavigationStack` — it is a shared destination, not a root route.

There is **no Settings screen.** Profile and sign-out live in the side menu; memberships live on the Gyms screen. Do not reintroduce bottom tabs or a Settings route.

### Visual design
- **Palette**: warm chalk background (`#F5F2EC`), ink text (`#1F1B16`), secondary `#6B6259`, tertiary `#9C9287`. Light mode only.
- **Primary action / brand**: forest green `#1F5C42`, with `#7BD6A6` as its on-dark accent. Clay for identity elements (avatar, app icon, member pin rings).
- **Busyness thresholds**: Quiet (`#2F9E66`, <40%), Moderate (`#C98A1E`, 40–70%), Packed (`#D9534F`, >70%).
- **Typography hierarchy**: Busyness always leads with the word, not the number (e.g., "Quiet" is primary, percentage is secondary).
- **Design Philosophy**: No all-caps tracked-out labels, no uniform card treatments. Hierarchy comes from differentiating components natively.

### Prototype ranking formula
```text
score = 100 − 0.6 × busy% − 0.5 × min(travelMinutes, 60) + 15 if member
Note: Includes a −60 penalty for closed gyms. Weights are designed to be user-configurable.
```

Distance is Haversine miles. If Mapbox is unreachable, fall back to `6 + miles × 2.3` for travel minutes so rankings never hard-fail. Scoring runs in plain Python rather than SQL, since weights are user-configurable and inputs come from two sources — this keeps it unit-testable.

### Key Decisions Made So Far
- **Auth**: sign-up + login, self-serve in the UI.
- **Gym set**: fixed, hand-curated Bay Area list.
- **Ranking formula**: two-stage distance filtering. Straight-line distance narrows the candidate gyms first, then Mapbox actual travel time is computed only for that narrowed set.
- **Data source**: Google's popular-times data, read from the rendered Maps page via a headless browser scrape. Verified working during prototyping; **not yet re-run across all 16 gyms.**
- **Repo**: monorepo — `backend/` (FastAPI + `uv`) and `app/` (Xcode + SPM) side by side.

### Accepted Risk
- **Data reliability**: Google's DOM can change without warning — this already happened once, killing the original `populartimes` approach. `aria-label` accessibility attributes are deliberately chosen as the most stable available surface.
- **Terms of Service**: Scraping Google Maps is against Google's ToS. Accepted as a conscious choice for a private, non-commercial project polling 16 venues.

## Technical Stack (v1)

**Platform**: Native iOS app built with Swift and SwiftUI.

### Backend
- FastAPI + Python 3.11, run locally during development.
- Supabase (Postgres) with PostGIS extension for the straight-line distance pre-filter.
- APScheduler **3.11.x** (not the perpetually-beta 4.0) running inside the FastAPI process for the recurring polling job.
- Playwright (headless Chromium), driven by that job — note this raises the hosting floor, since the host now needs a browser available.
- Supabase Auth issuing JWTs, verified by FastAPI via `PyJWKClient` (ES256). Supabase now signs with asymmetric ES256 keys published at `{SUPABASE_URL}/auth/v1/.well-known/jwks.json` — **not** the legacy HS256 shared secret found in older tutorials.
- Async SQLAlchemy 2.0 + asyncpg; FastAPI `lifespan` owns the engine and scheduler.

**Two gotchas worth not rediscovering:**
- Supabase's direct Postgres connection is **IPv6-only**. Use the Supavisor **session-mode** pooler (port 5432), which works over IPv4 and supports prepared statements. Transaction mode (6543) would force `statement_cache_size=0` + `NullPool` on asyncpg.
- Restrict Alembic autogenerate to the `public` schema, or it will try to drop Supabase's own `auth`/`storage` tables.

### Data ingestion
- **Headless-browser scrape of Google Maps**, driven by Playwright. One page load yields the full weekly curve *and* the live occupancy reading. Verified during prototyping; re-run across all 16 gyms before trusting a poll.
- **No Google Cloud project and no Places API key are needed** — gyms are located by search query, and nothing in this path touches a billed Google API.
- Parses `aria-label` accessibility attributes off the rendered "Popular times" chart. Two label formats:
  - `"31% busy at 10 AM."` — the weekly curve
  - `"Currently 54% busy, usually 58% busy."` — the live reading, which conveniently gives both the current value and its expected baseline, so drift is measurable for free
  - ⚠️ **The space before AM/PM is U+202F (narrow no-break space)**, not a normal space. Any regex must account for it.
- All 7 days are present in the DOM on a single page load: one bar per **open** hour per day, so the element count is gym-specific — ~126 (7 × 18) for a gym open 18 hours, far fewer for one like Mosaic Boulders at 10 hours on weekdays. Exactly one element — the current hour — carries the live label instead of an hourly one, so the current hour's bar is always absent from a scrape. Anchor on `div[role='region'][aria-label^='Popular times at ']`; each day is a child container, and exactly one has `aria-hidden` unset — that's the displayed day, named in plain text in the section header, which gives day attribution without assuming a Sunday-first ordering.
- The detail panel must be **scrolled** (~9 × 900px on `div[role='main']`) to lazy-load the section. Without scrolling you get 0 labels.
- Prefer `role` + `aria-label` selectors; obfuscated class names (`.g2BVhd`, `.C7xf8b`, `.zSdcRe`) will churn and should be treated as hints only.
- Page loads are **intermittently incomplete** (~5 in 6 succeed). Failure is unambiguous — a stunted page of ~772–974 chars with zero bars, versus ~2,740 chars and 125 bars on success — so wrap navigation in a retry loop (~6 attempts). Alert loudly if a parse returns 0 bars across *all* gyms, which signals a DOM change rather than a flaky load.
- Reuses one browser instance across all gyms per run, since a browser launch, not an HTTP request, is now the dominant cost.
- Playwright's sync API is blocking, so drive it via `run_in_threadpool` / `asyncio.to_thread` from the async scheduler job.
- Polling cadence: **30 minutes, during open hours only.** One scrape returns both the curve and the live reading, so there is no separate daily curve job. Skipping closed gyms cuts ~30% of the browser work, which is the dominant cost.
- Structure as a `CrowdProvider` protocol returning `CrowdReading(live_pct, weekly_curve)`, with a `GoogleMapsProvider` and a `FakeProvider` for tests. Failures logged and swallowed per-gym.
- ~~`populartimes`~~ was the original choice and has been **tested and abandoned**: unpublished on PyPI, last meaningfully updated 2021, and its scrape returns no popularity data at all as of Sept 2026. Its documented entry point also depends on the legacy Google Places API, closed to new Cloud projects since March 2025. `LivePopularTimes` fails identically. Plain HTTP fetching is impossible in any form — Google Maps serves a JavaScript-only shell.
- Per-gym native-occupancy override: **effectively ruled out.** Movement (4 gyms) and Touchstone (8 gyms) both run on Redpoint HQ, whose public portal exposes no occupancy or capacity data. That leaves at most Benchmark's 2 locations and the 2 independents. Asking Redpoint HQ or the gyms directly for API access remains worthwhile — first-party data would beat this and remove the ToS question — but it is not something to plan around.

### Routing
- Mapbox Matrix API for travel time on the narrowed candidate set (chosen for free tier limits).
- Cache aggressively: 3 locations × 16 gyms = 48 essentially-static pairs, refreshed on the order of weeks.

### Mobile app (iOS)
- Native SwiftUI (`App` lifecycle, `NavigationStack`, custom drawer implementation).
- MapKit via SwiftUI's `Map` view (dropping to `MKMapView` via `UIViewRepresentable` if custom clustering demands it).
- **MVVM architecture** utilizing SwiftUI's `@Observable` macro for state management.
- `URLSession` + `Codable` for API interactions (no third-party networking/state libraries).
- Supabase Auth via the official `supabase-swift` client, added through Swift Package Manager.

### iOS distribution
- Free Apple ID / Personal Team for building and running on your own device via Xcode.
- Apple Developer Program ($99/year) deferred until TestFlight is needed.

### Local development
- Build and run exclusively through Xcode.
- iOS Simulator hits the local FastAPI server via `localhost`; a physical device hits the Mac's LAN IP over the same Wi-Fi. ngrok / Cloudflare Tunnel as a cross-network fallback (and as a way to get HTTPS).
- iOS App Transport Security (ATS) exception required in `Info.plist` to allow HTTP traffic to the local FastAPI server during development.

### API contract skeleton
All `/api` routes require a Supabase Bearer token; JWT verification and handler logic are not
implemented yet, so the typed route skeletons return `501`. Supabase remains the direct
sign-up/login/logout surface.

- Gyms: `GET /api/gyms?at=` · `GET /api/gyms/{slug}?at=` ·
  `GET /api/gyms/{slug}/logo`. Gym detail consolidates hours, rates, links and the local day's
  forecast. Raw snapshots and curves are internal storage details, not separate endpoints.
- User: `GET /api/me` · `GET /api/me/memberships` ·
  `POST|DELETE /api/me/memberships/{gym_slug}` · `GET|POST /api/me/locations` ·
  `GET|PATCH|DELETE /api/me/locations/{location_id}`. User identity always comes from the JWT,
  never a path parameter.
- Rankings: `GET /api/rankings?at=&limit=` returns an independently ordered gym list for every
  saved location, allowing the app to switch between up to three locations without refetching.
  Ranked results include travel minutes, so the Mapbox cache has no public endpoint.

Successful JSON responses use `{"data": ...}`. Logo bytes and `204 No Content` mutations are
the exceptions. The unimplemented ranking-preferences API remains deferred with its UI.

### Schema
Designed and agreed — **`boulder_bay_schema.md` is the source of truth** for the reasoning;
the DDL itself lives in `backend/app/db/models.py`. Nine tables: `profiles` · `gyms` (bigint PK, unique `slug`, generated
`geog geography(Point,4326)` + GiST index) · `gym_hours` · `gym_memberships` · `saved_locations` ·
`busyness_snapshots` (the time series we own) · `busyness_curves` (Google's weekly histogram) ·
`ranking_prefs` · `travel_times` (Mapbox cache).

**Applied.** Alembic owns the application tables and generates them from
`backend/app/db/models.py`; two revisions are live — `7bea7599f868` (the nine tables) and
`b00fd69a53b6` (the sixteen-gym seed). See `boulder_bay_schema.md` §8.

## Seed data

The sixteen real Bay Area gyms — names, brands, cities, coordinates, rates and hours all
hand-verified. The source of truth is the seed migration `b00fd69a53b6`; the table below is a
readable summary of it, not a second copy to maintain.

| slug | name | brand | city | lat, lng | day / month |
|---|---|---|---|---|---|
| `mission` | Mission Cliffs | Touchstone | San Francisco | 37.7610, −122.4151 | $30 → $35 / $130 |
| `dogpatch` | Dogpatch Boulders | Touchstone | San Francisco | 37.7567, −122.3903 | $30 → $35 / $130 |
| `hyperion` | Hyperion Climbing | Touchstone | Redwood City | 37.4843, −122.2170 | $30 → $35 / $130 |
| `gwpc` | Great Western Power Company | Touchstone | Oakland | 37.8098, −122.2727 | $30 → $35 / $130 |
| `pipe` | Pacific Pipe | Touchstone | Oakland | 37.8156, −122.2913 | $30 → $35 / $130 |
| `ironworks` | Berkeley Ironworks | Touchstone | Berkeley | 37.8510, −122.2952 | $30 → $35 / $130 |
| `the-oaks` | The Oaks Climbing | Touchstone | Berkeley | 37.8916, −122.2807 | $30 → $35 / $130 |
| `studio` | The Studio Climbing | Touchstone | San Jose | 37.3302, −121.8885 | $25 → $30 / $112 |
| `mv-sf` | Movement San Francisco | Movement | San Francisco | 37.8042, −122.4708 | $33 / $115 |
| `mv-belmont` | Movement Belmont | Movement | Belmont | 37.5290, −122.2901 | $33 / $114 |
| `mv-mountain-view` | Movement Mountain View | Movement | Mountain View | 37.4029, −122.1163 | $33 / $121 |
| `mv-santa-clara` | Movement Santa Clara | Movement | Santa Clara | 37.3667, −121.9506 | $33 / $121 |
| `bm-sf` | Benchmark San Francisco | Benchmark | San Francisco | 37.7889, −122.4242 | $30 / $99 |
| `bm-berkeley` | Benchmark Berkeley | Benchmark | Berkeley | 37.8781, −122.2713 | $30 / $99 |
| `the-peak` | The Peak of Fremont | Independent | Fremont | 37.5106, −121.9535 | $30 / $72 |
| `mosaic` | Mosaic Boulders | Independent | Berkeley | 37.8675, −122.2614 | $22 / $75 |

**Day rates tier by time of day at Touchstone**: $30 before 3pm, $35 after — except The Studio,
which runs the same 3pm tier at its own prices, $25 before and $30 after. Every other gym charges
a flat day rate.

**Hours vary by gym and by weekday** — there is no house pattern. Movement closes at 18:00 Sunday
but 20:00 Saturday; Dogpatch and Pacific Pipe run an hour later on Tuesdays and Thursdays only;
Mosaic doesn't open until 13:00 on weekdays. All 112 rows are in the seed migration.
Between them the sixteen gyms are open 1,450 hours a week, which is what sets the polling volume
(~151k snapshots/year at 30-minute cadence).

**Addresses, website links and waiver links are filled in for all 16.** `address` is display
text only — map links are built at the app layer from `latitude`/`longitude` (Apple Maps via
`MKMapItem`, Google Maps via its universal link), so no map URL is stored. `google_maps_url` is
the one column still NULL for all 16, deliberately — it is optional, and nothing depends on it.
The sixteen `google_maps_query` strings have each been searched in Google Maps by hand and
resolve to the right venue.

Mockup saved locations: Home (Redwood City), Office (SoMa SF), Ryan's (Berkeley).

## Open Questions
1. **Ranking weights have no UI.** The plan requires them configurable; the mockup has no screen for them. Assumed: expose via `/api/me/prefs` with defaults, no app UI in v1.
2. ~~**Gym seed data is unverified.**~~ **Resolved.** All 16 gyms hand-verified — including
   addresses, website and waiver links, The Studio's $25/$30 tier, and that every
   `google_maps_query` resolves to the right venue. Seeded as revision `b00fd69a53b6`.
3. ~~**Poll cadence.**~~ **Resolved.** 30 minutes, open hours only. Tighten to 15 if the evening swing turns out under-sampled.
4. ~~**Whose hours win when Google disagrees with the seed?**~~ **Resolved by rule, not by
   picking a winner.** `gym_hours` bounds what is displayable, the curve fills it, falling back
   to the last value Google rendered and then to an explicit "no forecast". See
   `boulder_bay_schema.md` §3 and §6.10-6.11.
5. **Rate limiting / bot detection** was not observed across ~25 loads in one session, but was not stress-tested.
6. ~~**No tests, linting config, or CI** anywhere yet.~~ **Resolved.** Ruff + strict mypy + pytest on
   the backend, Swift Testing on the app, pre-commit hooks, and a GitHub Actions workflow running
   both. See `README.md`.

## Deferred for Later
- **Long-term hosting**: where FastAPI actually runs once local + tunnel testing isn't enough. Not worth deciding yet — but note the Playwright dependency means the host needs a browser available, so a plain small-tier Python dyno may not suffice.
