# Boulder Bay — v1 Tech Design (remaining features)

Status: **agreed, not yet built.** This is the build plan for everything v1 still lacks. It
sits beside `boulder_bay_plan.md` (product scope) and `boulder_bay_schema.md` (database design
record). Where this document changes a decision in either of them, it says so, and that file
links back here.

**Already built:** sign-up/login; the Map screen (gym pins, busyness on each pin and the gym card,
the hour slider); `GET /api/gyms`, which combines live snapshots with Google's weekly curves; and
a Playwright scraper that you run by hand as `uv run python -m app.scrape`.

**Still to build:**

| Area | Backend | App |
|---|---|---|
| Rankings | scoring, Mapbox travel times, `GET /api/rankings` | Rankings screen, "best right now" on the map |
| Your gyms and places | `/api/me`, memberships, saved locations (all return 501 today) | Gyms screen, location switcher, places sheet, first-place onboarding |
| Gym detail | `GET /api/gyms/{slug}`, best time to climb, logo bytes | Gym detail screen, logo loading |
| Navigation | — | hamburger side menu |
| Polling | APScheduler job every 30 min while gyms are open | — |

---

## 1. Decisions taken for this design

These were settled while writing this document. Each one changes or sharpens the plan.

1. **Saved locations are unlimited.** This replaces the plan's "home + a couple others". Each
   location has a **kind**: `home` (house icon), `work` (briefcase) or `other` (plain pin, no
   special meaning). Like Google Maps, a user has **at most one home and at most one work**;
   `other` is unlimited.
2. **At least one location is required, of any kind.** No particular kind is required. A new
   user adds a first place before reaching the map, and the last remaining place can't be
   deleted. The API enforces this, not the database: the signup trigger has no coordinates to
   create a place with, so a profile always exists briefly with zero places.
3. **Rankings covers one location per call: the one chosen in the switcher.** With unlimited
   locations, the stub's "every location in one response" would grow without bound and spend a
   Mapbox call on places the user isn't looking at. Switching location refetches, and that's
   cheap because travel times are cached (§7).
4. **Places can be edited from two places,** the location switcher's "Edit places" entry and a
   "Your places" row in the side menu. Both open the same sheet. There is still no Settings
   screen.
5. **The scheduler runs inside the FastAPI process,** as the plan says. A separate worker
   process was rejected: it means two things to run for a single-user dev setup, with no benefit
   until hosting is decided.
6. **Logos stay behind auth.** `GET /api/gyms/{slug}/logo` requires the Bearer token like every
   other `/api` route. So the app can't use `AsyncImage` and instead fetches the bytes through
   `APIClient`, keeping them in an in-memory cache only. That preserves "nothing cached on
   device in v1". Making the route public was rejected because it would break the one uniform
   auth rule for the sake of a convenience API.
7. **`ranking_prefs` rows are created lazily,** on the first rankings read, with
   `INSERT … ON CONFLICT DO NOTHING`. That keeps the defaults in the DDL where schema §2.8
   wants them, and needs no change to the Supabase signup trigger and no backfill of existing
   users. There is **no prefs API and no weights UI in v1** (this resolves plan Open Question 1).
8. **`is_member` moves onto `Gym`.** The map needs it for member pin rings on `/api/gyms`, and
   Rankings embeds the same `Gym`. `RankedGym.is_member` is removed so the fact lives in one
   field. *Open to change.*

---

## 2. Build order

Seven slices. Each is its own PR, passes CI on its own, and leaves the app working.

| # | Slice | Why here |
|---|---|---|
| 1 | **Scheduler** | Smallest and backend-only. Every day it runs earlier is a day more of owned snapshot data. |
| 2 | **Profile, memberships, places API** + `saved_locations.kind` migration | Everything in the app shell reads these. |
| 3 | **App shell**: drawer, `AppModel`, location switcher, places sheet, first-place onboarding | Gives Rankings and Gyms somewhere to live. |
| 4 | **Gyms screen** and member rings on map pins | First consumer of memberships. |
| 5 | **Logos**: endpoint + `LogoStore` | Detail and Rankings both show logos. |
| 6 | **Gym detail**: endpoint, best time, screen | Shared destination for Map, Rankings and Gyms. |
| 7 | **Rankings**: Mapbox, cache, scoring, endpoint, screen, map "best right now" | Depends on places, memberships, logos and the busyness helper refactored in 6. |

**Out of scope, unchanged from the plan:** map clustering priority, real-time GPS, a
ranking-weights UI, long-term hosting.

---

## 3. Schema change

One Alembic revision on top of `b91e4d2c7a60`, applied to the hosted database in slice 2.

```text
saved_locations.kind  text not null default 'other'
  check (kind in ('home', 'work', 'other'))         -- saved_locations_kind_valid
unique index saved_locations_one_home_idx (user_id) where kind = 'home'
unique index saved_locations_one_work_idx (user_id) where kind = 'work'
```

- `text` + `check`, not a Postgres enum, for the same reason as `gyms.brand`: enums are painful
  to alter.
- Partial unique indexes, not constraints, for the same reason as
  `saved_locations_one_default_idx` (schema §2.7): constraints can't be partial.
- The "at least one location" rule has **no** DDL. A check constraint can't count rows, and a
  trigger would block the account's own cascade delete.
- No other DDL is needed. `ranking_prefs` and `travel_times` already exist and are unused.

**Procedure:** add the column and indexes to `SavedLocation` in `models.py`, then
`alembic revision --autogenerate`. Read the diff and confirm it touches neither `geog` nor
`profiles_id_fkey` before running `upgrade head` against the hosted database. In the same PR,
update `backend/CLAUDE.md` "Database state", the root `CLAUDE.md` revision pointer, schema §2.7
and §8, and the constraint and index names in `tests/test_models.py`.

---

## 4. Backend: profile, memberships, places

New `app/services/me.py`. `app/api/routers/me.py` swaps its 501s for calls into it. As
everywhere, identity comes from the JWT's `sub` and never from a path, and a slug is resolved to
`gym_id` once at the edge.

### Profile
`GET /api/me` → `UserProfile`, read from `profiles`. Returns 404 if the row is missing. The
signup trigger should make that impossible, but a clear 404 beats a 500 if it ever happens.

### Memberships
- `GET /api/me/memberships` → slugs, ordered by gym name.
- `POST /api/me/memberships/{slug}` → 204. `INSERT … ON CONFLICT DO NOTHING`, so it is
  idempotent.
- `DELETE /api/me/memberships/{slug}` → 204, and idempotent too.
- An unknown or inactive slug → 404 on both.

The schema doc's `PUT /api/me/memberships` (replace the whole set) is **not** built. The mockup's
Gyms screen toggles one gym at a time, and there is no chain-wide toggle in v1.

### Saved locations
`kind` is added to `SavedLocation`, `CreateSavedLocation` (required) and `UpdateSavedLocation`
(optional).

| Operation | Rule |
|---|---|
| list | Creation order. |
| create | The user's first location becomes the default whatever its kind. `make_default=true` promotes it. No count cap; the old "three allowed" docstring goes. |
| update | Only supplied fields change. Changing `kind` is allowed if it doesn't create a second home or work. Changing `latitude`/`longitude` also deletes that location's `travel_times` rows: the PK is unchanged, so the cascade won't fire. |
| promote | `make_default=true` clears the current default, then sets this one, in one transaction. That order is what the partial unique index requires (schema §2.7). |
| delete | **409** if it is the user's only location. If it was the default, the oldest remaining location becomes the default in the same transaction. |

**Errors.** A unique violation is mapped to **409** by constraint name: duplicate label, second
home, or second work, each with its own detail message the app can show. Another user's
location id returns **404**, never 403, so ids can't be probed.

### Tests
Router tests follow `tests/test_gyms_router.py`: override `require_user`/`get_session` and mock
the service module. Service tests use a fake session, as `tests/test_services_gyms.py` does.
They cover the default rules, the last-location 409, the lat/lng change clearing travel times,
and the constraint-name → message mapping.

---

## 5. Backend: logos

`GET /api/gyms/{slug}/logo`:

- One query: `gym_logos.image, content_type, sha256` joined through `gyms.logo_id`.
- Returns `Response(content=image, media_type=content_type)` with `ETag: "<sha256>"` and
  `Cache-Control: private, max-age=86400`.
- `If-None-Match` matching the ETag → **304** with no body. This is the job `sha256` was stored
  for (schema §2.10).
- An unknown slug, or a gym with a NULL `logo_id`, → **404**.

`to_api_gym` fills in `logo_url` with `request.url_for("get_gym_logo", slug=row.slug)` when
`logo_id` is set, and leaves it `None` otherwise. The URL is absolute (it is typed `AnyHttpUrl`),
so the services need the `Request`, or a base URL, passed in. Nothing else about `Gym` changes.

---

## 6. Backend: gym detail and best time to climb

### Endpoint
`GET /api/gyms/{slug}?at=` → `GymDetail`, which already exists as a model:

- `gym` (the same `Gym` the list returns, busyness resolved for `at`), `address`, `timezone`,
  `website_url`, `waiver_url`
- `hours`: all seven `gym_hours` rows
- `rates`: the four rate columns, unchanged
- `forecast`: a `BusynessForecast` for **the gym's local calendar day containing `at`**

An unknown or inactive slug returns 404. `at` without an offset returns 422, the same as the
list.

### Forecast points
One `ForecastPoint` per local hour the gym is open that day: the hours from `opens_at` to
`closes_at` that `open_during` (in `scrape/poll.py`) accepts. Each point is resolved with the
existing `resolve_busyness`, so the chart tells the same story as the map:

- finished hours → `observed` (the mean of that hour's snapshots), falling back to the curve
- the current hour → `live` when fresh
- later hours → `forecast` from the curve, or no value ("no forecast"), never 0

`ForecastPoint` gains a `source: BusynessSource | None` so the app can dim past hours and
highlight live. Loading takes one curve query (the gym's rows for that day of the week) and one
snapshot query (the gym's snapshots inside that local day, plus the live window).

### Best time to climb
A pure function in `services/busyness.py`:

> Among the gym's open hours on that local day that start **after** `at`'s local hour, pick
> the one with the lowest **curve** `busy_pct`. Ties go to the earliest hour. Hours with no
> curve row can't be picked. If nothing qualifies, return `None`.

- It uses the curve, not live or observed values, because it predicts the future (schema §3:
  "Google's forecast is the forecast").
- `None` means "closes soon" or "no forecast left today". The app renders that text; the API
  doesn't.
- It is scoped to the remainder of the requested day, matching the mockup and the plan's "the
  future open hour with the minimum predicted busyness". Scanning into tomorrow was rejected:
  "best time" on a detail screen dated today would then quietly point at a different day.

### Refactor
`list_gyms` loads hours, curve rows and snapshots and then resolves each gym. Extract that into
a helper (`load_busyness_inputs` + `resolve_for`) so the list, the detail and the ranking all
resolve busyness through the same code, with the four-query bound kept.

---

## 7. Backend: rankings

### Endpoint
`GET /api/rankings?location_id=&at=&limit=` → `{at, location, ranked_gyms}`.

- `location_id` is the location chosen in the app's switcher, which the app always sends. If it
  is left out, the user's default location is used.
- Unknown or another user's `location_id` → 404.
- A user with no locations → **409** "a saved location is required". The app treats that as
  "show first-place onboarding" (§9).
- `limit` stays 1–16.

`Rankings` becomes `{at: datetime, location: SavedLocation, ranked_gyms: list[RankedGym]}`, and
`LocationRankings` is deleted (see §10).

### Stage 1: straight-line prefilter
```sql
select … from gyms
where is_active
  and extensions.st_dwithin(gyms.geog, :location_geog, :radius_meters)
```
`radius_meters` defaults to 80,467 (50 mi), as `Settings.ranking_radius_meters`. Gyms outside
the radius aren't ranked. Use `ST_DWithin` and never `ST_Distance <= x` (schema §4), so
`gyms_geog_idx` does the work. At 50 mi, every Bay Area location sees nearly all sixteen gyms,
and the cap is what stops a far-away "other" place (say, Tahoe) from ranking Bay Area gyms at
all.

### Stage 2: travel minutes, `app/services/travel.py`
- `MapboxClient`: httpx, the Matrix API with the `driving` profile (not `driving-traffic`; the
  cache lives for weeks, so live traffic would be stale anyway). One request: one source plus
  ≤16 destinations, well under the 25-coordinate limit.
- `travel_minutes(session, location, gyms) -> dict[gym_id, (minutes, provider)]`:
  1. Read `travel_times` for `(location_id, gym_id in candidates)`.
  2. A row is **fresh** if `provider='mapbox'` and it is under 30 days old, or
     `provider='haversine_fallback'` and it is under 1 hour old.
  3. Fetch only the missing or stale pairs from Mapbox in one call, then upsert them.
  4. If Mapbox errors or times out (5 s), or `MAPBOX_TOKEN` is empty, compute
     `6 + miles × 2.3` from the haversine distance and upsert it as `haversine_fallback`.
- **Rankings never fails because of Mapbox.** The fallback is what the `provider` check
  constraint was designed for (schema §2.9).
- Free-tier use: about one Matrix call per place per 30 days.

### Scoring, `app/services/ranking.py`
A plain function, as the plan asks: no SQL, unit-testable.

```text
crowd   = 0 if closed else (busy_pct if known else 50)
score   = 100
        − w_crowd    × crowd
        − w_travel   × min(travel_minutes, travel_cap_minutes)
        + member_boost   if member
        − closed_penalty if closed
```

- **Weights** come from `ranking_prefs`, created lazily:
  `INSERT … (user_id) ON CONFLICT DO NOTHING`, then `SELECT`. Defaults are 0.6 / 0.5 / 15 /
  60 / 60, the prototype formula, so an untouched account scores like the mockup.
- **Busyness** is resolved for `at` through the §6 helper, so live, observed and forecast mean
  the same thing as on the map.
- **Unknown busyness while open counts as 50** (neutral, the middle of Moderate). Treating it
  as 0 would make a scraper gap look like the best gym in the Bay. Dropping the gym would hide
  an open gym. *Open to change.*
- **Order:** score descending, then travel minutes ascending, then name. `rank` is 1-based
  after sorting. `score` is returned unrounded, and the app rounds it for display.

### Settings
`MAPBOX_TOKEN` is already in `.env.example`. Add `RANKING_RADIUS_METERS` (with a comment) to
`Settings` and `.env.example`.

### Tests
- Table tests for `score()` that reproduce the mockup's numbers.
- `travel_minutes` with `httpx.MockTransport`: fresh cache (no request made), stale rows
  (one request, only stale pairs), and a 500 response or no token (fallback rows written).
- Router: the 404 and 409 cases, and the default-location fallback.

---

## 8. Backend: scheduler

New `app/scrape/scheduler.py`; `app/main.py`'s `lifespan` owns it next to the engine.

```text
lifespan:
  engine, session_factory = …
  if settings.scheduler_enabled:
      scheduler = AsyncIOScheduler(timezone="UTC")
      scheduler.add_job(poll_tick, CronTrigger(minute="0,30"),
                        max_instances=1, coalesce=True, misfire_grace_time=300,
                        args=[session_factory, settings])
      scheduler.start()
  yield
  scheduler.shutdown(wait=False); await engine.dispose()
```

- **`SCHEDULER_ENABLED`** defaults to `false`, so tests, CI and an ordinary `uvicorn` dev run
  never launch Chromium. Add it to `.env.example`.
- **`poll_tick`**:
  1. `tick = now` truncated to :00 or :30. It becomes `observed_at`, which schema §2.4 says is
     "the poll tick, not `now()`", so a late or duplicate run hits the
     `(gym_id, observed_at)` unique key and is a no-op.
  2. Load gyms and hours. `load_gyms` moves from `scrape/__main__.py` to `scrape/poll.py` so
     both the CLI and the job use it.
  3. Keep only gyms where `resolve_is_open(tick, …)` is true. If there are none, log at debug
     level and return without launching a browser. This is where the plan's "~30% less browser
     work" comes from.
  4. Open one `GoogleMapsProvider` for the run, call the existing `run_poll`, and close the
     provider. One browser per run, not one per process lifetime, so a wedged Chromium can't
     outlive a tick.
  5. Log the summary. Log **ERROR** on `summary.no_data` (a DOM change, per the plan) and on
     `ProviderUnavailable` (the Google sign-in expired). **Never raise out of the job:**
     APScheduler would only log it, and the next tick should still run.
- The one-shot CLI becomes a thin wrapper over the same "load, filter, poll" helper. It keeps
  `--gym` and `--dry-run`, and **doesn't** filter by open hours unless asked (`--open-only`),
  so you can still scrape a closed gym on purpose.

**Operational constraints**, which will go in the README:
- Run uvicorn with **one worker and without `--reload`** whenever the scheduler is on. Each
  worker process, and each reload, starts its own scheduler, and `max_instances` is per
  process.
- The host needs full Chromium and the signed-in profile at `SCRAPE_PROFILE_DIR`.
  `python -m app.scrape --login` is still a manual, occasional step.

**Tests:** tick truncation, the open-gym filter (including a day with no `gym_hours` row), a job
run with a fake provider and a fake session factory, and the job swallowing
`ProviderUnavailable`. The `lifespan` test asserts that no scheduler starts when the flag is
off.

---

## 9. App architecture

### Shared state: `AppModel`
`@MainActor @Observable final class AppModel`, created in `AppContainer` and passed down.

| Property | Source | Used by |
|---|---|---|
| `profile: UserProfile?` | `GET /api/me` | drawer header |
| `locations: [SavedLocation]` | `GET /api/me/locations` | switcher, places sheet, onboarding gate |
| `selectedLocationID: UUID?` | starts as the default location | switcher, map camera, rankings |
| `memberships: Set<String>` | `GET /api/me/memberships` | Gyms screen, member pin rings |
| `selectedHour: Int` | moved up from `MapViewModel` | Map **and** Rankings share one time, as in the mockup |

- `AppModel.bootstrap()` runs once after sign-in and loads profile, locations and memberships
  concurrently.
- Membership toggles are **optimistic**: flip the set, call the API, and roll back with an error
  banner on failure.
- `MapViewModel` keeps gyms, selection and loading. It reads `selectedHour` and the selected
  location from `AppModel`.

### Networking
`APIClient` gains:
- `send(method:path:body:)`, with `post`/`patch`/`delete` wrappers that handle 204, and the same
  error mapping `get` uses. `APIError` gains `.conflict(String)`, decoded from FastAPI's
  `{"detail": …}`, so 409 messages ("You already have a home") reach the UI.
- Typed calls for every endpoint in §4–§7, plus `logo(slug:) -> Data`.

### Root and shell
`RootView` becomes a four-way gate:

1. restoring session → spinner
2. no session → `AuthenticationView`
3. session, `locations.isEmpty` → **`FirstPlaceView`**
4. otherwise → **`AppShell`**

The temporary sign-out overlay goes away.

**`FirstPlaceView`** (`Features/Places/`) is a full-screen "Add a place" step that can't be
dismissed. It has a kind picker (Home preselected, but any kind works), a label, and address
search. Saving creates the location, which becomes the default, and the gate falls through to
the shell. Existing test accounts have no places, so they land here once. That's intended.

**`AppShell`** (`App/AppShell.swift`):
- `NavigationStack(path:)`. Its root view switches on `AppRoute` (`.map`, `.rankings`, `.gyms`);
  it is not a `TabView`.
- A hamburger button in the top-leading toolbar of each root screen.
- **Drawer:** a custom overlay sliding from the leading edge over a dimmed backdrop, with
  ~0.3 s ease-out timing to match the mockup. Tapping the backdrop or swiping it away closes
  it. Contents, top to bottom:
  - a clay avatar with the display name's initials; tapping it expands to show **Sign out**
  - **Map / Rankings / Gyms** rows, with the active one tinted `#EDE7DD`
  - a **Your places** row that opens the places sheet
- **Gym detail is a shared destination:**
  `.navigationDestination(for: GymRoute.self) { GymDetailView(slug:) }` on the stack, reached
  from the map card, a Rankings row and a Gyms row.
- No bottom tabs and no Settings screen (root `CLAUDE.md`).

### Places
- **`LocationSwitcher`**: a chip on the Map and Rankings screens showing the selected place's
  icon and label. Its menu lists every place: `house.fill` for home, `briefcase.fill` for work,
  `mappin` for other. A checkmark marks the selected one, and the last entry is **Edit
  places…**. Picking a place sets `selectedLocationID`; the map flies to it and Rankings
  refetches.
- **`PlacesView`** (a sheet; the same view from the switcher and the drawer):
  - The list has kind icons, a "Default" tag, swipe to delete, and "Make default".
  - The last remaining place has no delete action, as a UI mirror of the API's 409.
  - The add/edit form:
    - A kind picker that hides **Home** once a home exists and **Work** once a work exists
      (except when editing that same place).
    - A label, prefilled with "Home" or "Work" for those kinds and free text for other.
    - Address search with `MKLocalSearchCompleter` for suggestions, then `MKLocalSearch` to
      resolve the chosen one to coordinates and a display address. This is the "coordinates
      come from the app's MapKit place search" that `CreateSavedLocation` already documents.

### Gyms screen
Follows the mockup: a "Your gyms" list (or "None yet"), plus a search field over all sixteen
gyms matching name, city and brand. Each row has an **Add** button (forest green) or **Added**
(neutral). Tapping a row pushes detail. The gym list comes from the same `/api/gyms` call the
map uses, kept on `AppModel`, so the screen makes no extra request.

### Map additions
- Member gyms' pins get the clay ring (`#B8623A`), and member pins draw above the others.
- A **"Best right now" / "Best at 7 PM"** button calls rankings for the selected location and
  hour, then selects and flies to rank 1.
- The selected gym card pushes `GymRoute`.

### Rankings screen
- Header: the location switcher and the time ("Live, 5 PM" or "Forecast for 7 PM"), driven by
  `AppModel.selectedHour`.
- **Best-pick card** on forest green (`#1F5C42`):
  - The logo is template-rendered with a light tint, so black marks stay visible (schema §7).
  - The name, busyness word first and then the percentage, and travel minutes.
  - A "why" line using the mockup's rule: *"Your gym, and it's quiet right now"* for a member
    gym, otherwise *"Quiet right now and close to Home"*.
- Then rows 2…n: rank, logo chip, name and city, busyness ("Moderate · 52%"), "18 min", and a
  member tag. Closed gyms read "Closed".
- Pull to refresh. A 409 sends the user to onboarding, which shouldn't happen past the gate.

### Gym detail screen
Top to bottom, following the mockup and plan Core Feature 7:

1. Logo and name; brand and city.
2. **Address**: tapping it opens Apple Maps via `MKMapItem` built from latitude/longitude
   (schema §7 — no stored map URL).
3. **Hours**: today's, with the week expandable and today in bold.
4. **Busyness**: "Right now" or "At 7 PM", word first then percentage, or "Closed" / "No
   forecast".
5. **Forecast chart** (Swift Charts, part of the SDK, so no `project.yml` change): one bar per
   open hour, colored by level. Past hours are dimmed, and the selected hour is at full
   strength.
6. **Best time** card: "4 PM – 5 PM · quiet, about 28%", or "Closes soon" when `best_time` is
   null.
7. **Rates**: "Day pass $30 before 3 PM · $35 after" for tiered gyms, otherwise one price; then
   "Monthly $130".
8. **Waiver** and **Website** links, each shown only when its URL is set.

### Logos
- **`LogoStore`** (an actor): an in-memory `[slug: UIImage]` cache with in-flight request dedup.
  It fetches through `APIClient`, so the Bearer token is attached. It uses a `URLSession` whose
  `urlCache` is `nil`, so **nothing is written to disk**. The cache dies with the process, which
  is the v1 choice.
- **`LogoImage(slug:)`** view: shows the cached image, or a clay chip with the gym's initials
  while loading or on failure. It takes a `tint` parameter for the best-pick card.

### Tests
- **Unit tests** (Swift Testing + `StubURLProtocol`, following `MapViewModelTests`):
  - `AppModel`: bootstrap, optimistic toggle rollback, location selection fallback
  - the places form's kind-availability rules
  - rankings and detail view models
  - `APIClient` 204/409 handling
- **Snapshot tests**, following `app/CLAUDE.md` (look at every re-recorded PNG): drawer,
  rankings row, best-pick card, detail header, best-time card. `MapView` stays un-snapshotted
  (MapKit tiles).

---

## 10. API contract changes

Each change lands on both sides in the same PR, so `tests/test_api_contract.py` and
`APIResponseModelDecodingTests` stay in step.

| Model / route | Change | Slice |
|---|---|---|
| `SavedLocation`, `CreateSavedLocation`, `UpdateSavedLocation` | **+ `kind`**: `home` / `work` / `other` | 2 |
| `POST /api/me/locations` | no count cap; 409 for duplicate label / second home / second work | 2 |
| `DELETE /api/me/locations/{id}` | 409 for the last location | 2 |
| `Gym` | **+ `is_member: bool`** | 4 |
| `Gym.logo_url` | now filled in | 5 |
| `ForecastPoint` | **+ `source`** | 6 |
| `GET /api/rankings` | **+ `location_id`**; response is one location | 7 |
| `Rankings` | `{at, location, ranked_gyms}`; `LocationRankings` removed | 7 |
| `RankedGym` | **− `is_member`** (now on `gym`) | 7 |

---

## 11. Risks and open questions

- **A Google sign-in expiry stops polling,** and only the logs say so. Cheap follow-up: a
  `last_successful_poll_at` field on `/health`, read from `max(busyness_snapshots.observed_at)`.
- **The scheduler runs inside the API process.** If it ever gets hosted with multiple workers,
  move the job to its own process or add a Postgres advisory lock. Out of scope until hosting is
  decided.
- **Neutral 50 for an unknown busy percentage** is a judgment call (§7).
- **Mapbox free tier.** Around one call per place per 30 days isn't a risk at this scale.
- **The 50-mile radius** is a constant in settings, not a per-user preference.
