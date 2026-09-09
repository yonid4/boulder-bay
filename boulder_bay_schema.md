# Boulder Bay — Database Schema (v1)

Status: **applied.** §6 records the settled decisions; §7 lists what's still open. This document
is the design record — the reasoning, and the alternatives that were rejected. What actually
runs is `backend/app/db/models.py` and two Alembic revisions; see §8.

Scope comes from `boulder_bay_plan.md` § "Planned schema" and the endpoint list. Conventions:
Postgres 15 (Supabase), `snake_case`, plural table names, `timestamptz` everywhere, everything
in `public` except PostGIS types (which live in `extensions`, per the existing migration).

---

## 1. Overview

```
auth.users (Supabase-owned)
   │ 1:1
   ▼
profiles ──1:1── ranking_prefs
   │
   ├──1:N── saved_locations ──1:N── travel_times ──N:1── gyms
   │
   └──M:N── gym_memberships ──────────────────────────── gyms
                                                          │
                                    ┌─────────────────────┼─────────────────────┐
                                    ▼                     ▼                     ▼
                              gym_hours          busyness_snapshots      busyness_curves
                          (when it's open)    (time series we own)   (Google's weekly curve)
```

Nine tables. Three groups:

| Group          | Tables                                                                           | Written by                           |
| -------------- | -------------------------------------------------------------------------------- | ------------------------------------ |
| Reference data | `gyms`, `gym_hours`                                                              | seed migration + scraper cross-check |
| Observed data  | `busyness_snapshots`, `busyness_curves`                                          | the APScheduler poll job             |
| User data      | `profiles`, `gym_memberships`, `saved_locations`, `ranking_prefs`, `travel_times` | the API                              |

**Keys.** `gyms` uses a surrogate `bigint` PK with `slug` as a unique natural key; every FK
points at `gym_id`. `saved_locations` uses `uuid` because its id is handed to the client in
`GET /api/rankings?location_id=` and shouldn't be enumerable. `profiles.id` is the Supabase
`auth.users` uuid.

---

## 2. Tables

### 2.1 `profiles`

One row per account. Mirrors `auth.users` so the rest of the schema can have real foreign keys
without reaching into Supabase's `auth` schema for anything but identity.

| column         | type                                 | notes                                     |
| -------------- | ------------------------------------ | ----------------------------------------- |
| `id`           | `uuid` PK                            | FK → `auth.users(id)` `on delete cascade` |
| `display_name` | `text`                               | nullable; shown in the side menu          |
| `created_at`   | `timestamptz not null default now()` |                                           |
| `updated_at`   | `timestamptz not null default now()` |                                           |

**Decision:** the row is created lazily by FastAPI on the first authenticated request
(`GET /api/me` upserts), _not_ by a trigger on `auth.users`. Keeps account bootstrapping in
testable Python instead of a DB trigger that touches a schema Alembic can't see.

### 2.2 `gyms`

The sixteen curated gyms. Revision `b00fd69a53b6` holds the seed and is the source of truth
for their data.

| column                      | type                                          | notes                                                                                                   |
| --------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `id`                        | `bigint generated always as identity` PK      | internal only; never appears in the API                                                                 |
| `slug`                      | `text not null unique`                        | `check (slug ~ '^[a-z0-9-]+$')`, e.g. `mv-belmont`; the public identifier in `GET /api/gyms/{slug}`      |
| `name`                      | `text not null`                               | "Movement Belmont"                                                                                      |
| `brand`                     | `text not null`                               | `check in ('movement','touchstone','benchmark','independent')`                                          |
| `city`                      | `text not null`                               |                                                                                                         |
| `address`                   | `text`                                        | nullable — unknown until the verification pass; see §2.2 note                                           |
| `latitude`                  | `double precision not null`                   | `check between -90 and 90`                                                                              |
| `longitude`                 | `double precision not null`                   | `check between -180 and 180`                                                                            |
| `geog`                      | `extensions.geography(Point,4326)`            | **generated stored** from lat/lng; GiST index                                                           |
| `timezone`                  | `text not null default 'America/Los_Angeles'` | all sixteen agree today, but "best time to climb" is a clock-time calculation and shouldn't hardcode a zone |
| `google_maps_query`         | `text not null`                               | search string the scraper falls back to                                                                 |
| `google_maps_url`           | `text`                                        | canonical `/maps/place/…` link; preferred when known — skips search disambiguation                      |
| `website_url`               | `text`                                        |                                                                                                         |
| `waiver_url`                | `text`                                        | nullable — not every gym publishes one; all NULL until verified                                         |
| `day_pass_cents`            | `integer`                                     | base / off-peak day rate. `check >= 0`; integer cents, never float money                                |
| `day_pass_peak_cents`       | `integer`                                     | NULL for a flat day rate                                                                                |
| `peak_starts_at`            | `time`                                        | local clock time the peak rate begins; NULL for a flat day rate                                         |
| `monthly_cents`             | `integer`                                     | `check >= 0`                                                                                            |
| `is_active`                 | `boolean not null default true`               | retire a gym without orphaning its time series                                                          |
| `created_at` / `updated_at` | `timestamptz`                                 |                                                                                                         |

Indexes: `gist(geog)` for the straight-line pre-filter; `unique(slug)` for the API lookup.
`(is_active)` is not worth an index at n=16.

**Decisions worth your eye:**

- **Surrogate `id` + unique `slug`.** The slug stays the public identifier — routes, seed data,
  and app-bundle logo assets are all keyed by it — but nothing _references_ it. Renaming a slug
  is a one-row update instead of a cascade through five tables, and the FK in
  `busyness_snapshots` is 8 bytes instead of ~12 across 100k+ rows. `bigint` rather than `uuid`
  because gym rows are never client-generated and never merged across databases.
- **Two scraper targets, not one.** `google_maps_query` (a search string) can land on a
  multi-result disambiguation feed instead of the place panel; a canonical `/maps/place/` URL
  goes straight there. `google_maps_url` is nullable and backfilled once each gym's link is
  verified, with the query as the fallback. This does _not_ fix the known flakiness — the
  ~1-in-6 stunted page loads are a lazy-render failure, not a search-resolution one, so the
  retry loop stays either way.
- **Day rates tier by time of day.** Touchstone charges $30 before 3pm and $35 after, so a
  single `day_pass_cents` can't render the detail screen honestly. Three columns rather than a
  `gym_rates` table: there is exactly one tiering pattern in the real data, one threshold, one
  chain, and a rates table would turn the flat-rate common case (12 of 16 gyms) into a join plus
  a row for the sake of student rates and punch cards that aren't in scope. If a gym ever
  introduces weekend pricing, the two columns become two rows and the migration is small.
  `check (num_nulls(day_pass_peak_cents, peak_starts_at) <> 1)` rejects half a tier, which can't
  be displayed. Stored per-gym, not per-brand: Touchstone's seven other gyms run $30→$35, but The
  Studio runs the same 3pm tier at $25→$30, so a brand-level rate would already be wrong on day
  one. Price is display-only; it does not enter the ranking formula.
- `latitude`/`longitude` are the source of truth (that's what the seed table and the app's
  MapKit pins want), and `geog` is a `generated always as (...) stored` column derived from
  them. One place to edit, no drift. Fallback if the generated-column expression gives Postgres
  trouble: a plain column plus a `before insert/update` trigger.
- `brand` is `text` + `check`, not a Postgres `enum` — enums are painful to alter in migrations
  and this one will grow if an independent gets added.
- `address`, `website_url` and `waiver_url` seed as NULL rather than invented. A fabricated
  street address would sit behind the detail screen's "open in Apple Maps" tap; the app falls
  back to lat/lng for that link until the verification pass fills them in.
- No logo column. Logos ship as app-bundle assets keyed by `slug`.

### 2.3 `gym_hours`

Opening hours per weekday. Needed by four things: the detail screen, the −60 closed-gym penalty
in ranking, "best time to climb" (= the future **open** hour with the minimum predicted
busyness), and disambiguating missing curve rows (§3).

| column        | type                    | notes                                                                                                                                   |
| ------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `gym_id`      | `bigint`                | FK → `gyms` `on delete cascade`                                                                                                         |
| `day_of_week` | `smallint`              | `check between 0 and 6`, **0 = Sunday** (matches Postgres `extract(dow)`; Swift's `Calendar.weekday` is 1-based, so the app subtracts 1) |
| `opens_at`    | `time not null`         |                                                                                                                                         |
| `closes_at`   | `time not null`         | `check (closes_at > opens_at)` for v1                                                                                                   |
| PK            | `(gym_id, day_of_week)` |                                                                                                                                         |

112 seed rows (16 gyms × 7 days), transcribed per gym — the weekday/weekend patterns don't
hold, so they aren't generated. Times are naked `time` values, interpreted in the gym's own
`timezone`.

Past-midnight closing is deliberately rejected by the check constraint for v1; no seed gym does
it, and allowing it forces every "is it open now" query to branch.

### 2.4 `busyness_snapshots`

The time series we own — one row per gym per poll (30 min, open hours only).

| column        | type                                     | notes                                                                                                    |
| ------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `id`          | `bigint generated always as identity` PK |                                                                                                          |
| `gym_id`      | `bigint`                                 | FK → `gyms` `on delete cascade`                                                                          |
| `observed_at` | `timestamptz not null`                   | truncated to the poll tick, not `now()`                                                                  |
| `live_pct`    | `smallint`                               | `check between 0 and 100`; **nullable** — Google omits live data when a venue is quiet or closed         |
| `typical_pct` | `smallint`                               | `check between 0 and 100`; the "usually 58% busy" half of the same label, so drift is measurable for free |
| `source`      | `text not null default 'google_maps'`    | lets `FakeProvider` rows be told apart in tests                                                          |
| unique        | `(gym_id, observed_at)`                  | makes a re-run of a poll idempotent; its btree also serves the "latest reading per gym" read, so there is no second index |

**Volume.** At 30 minutes, open hours only — Google reports no live occupancy for a closed
venue, so those scrapes return nothing anyway. The sixteen seeded gyms are open 1,450 hours a
week between them, so that's **~151k rows/year, ≈19 MB** including indexes. Small enough that no partitioning, retention job, or rollup is warranted. The
constraint that actually binds is Playwright runs, not rows: skipping closed gyms cuts ~30% of
the browser work, which is the dominant cost in the poll job.

**Reading "latest per gym" is cheap and stays cheap.** `distinct on (gym_id) … order by gym_id,
observed_at desc` against the `(gym_id, observed_at)` btree is sixteen index descents —
O(n_gyms · log n),
so it does not degrade as the series grows. See §5 for why the latest reading is not cached onto
`gyms`.

**Why keep every poll,** when v1 only ever reads the latest row per gym? Because this is the one
dataset the project owns rather than re-scrapes: it makes `live_pct`-vs-`typical_pct` drift
measurable, it's how you'd notice the scraper silently degrading, and it's the time series the
plan's backend goals are built around. It is explicitly **not** a prediction input — see §3.

### 2.5 `busyness_curves`

Google's typical-week histogram. Drives the map time scrubber and "best time to climb".

| column        | type                                 | notes                                              |
| ------------- | ------------------------------------ | -------------------------------------------------- |
| `gym_id`      | `bigint`                             | FK → `gyms` `on delete cascade`                    |
| `day_of_week` | `smallint`                           | `check between 0 and 6`, same 0 = Sunday convention |
| `hour_of_day` | `smallint`                           | `check between 0 and 23`                           |
| `busy_pct`    | `smallint not null`                  | `check between 0 and 100`                          |
| `updated_at`  | `timestamptz not null default now()` | last time Google confirmed this bar                |
| PK            | `(gym_id, day_of_week, hour_of_day)` | every refresh is a plain upsert                    |

**Current curve only** — no history of past curves. Nothing in v1 reads a historical curve, and
`busyness_snapshots` already preserves the real observations. Add a `captured_on` date to the PK
later if you ever want to watch the curve itself shift seasonally.

**The current hour is always missing from a scrape.** Of the 126 elements on the page, 125 carry
an hourly label and exactly one — the current hour — carries the live label instead. So an
upsert writes the 125 bars it got and leaves the current hour's stored row untouched. Never
delete-then-insert the curve, or you'll punch an hourly hole in it every run.

**Closed hours have no row, and that is correct.** Google renders ~18 bars per day, so hours
0–5 are simply absent. They are deliberately _not_ seeded as `busy_pct = 0`: a fabricated zero
is indistinguishable from a genuinely empty gym and would destroy the only signal available. A
missing row means "no data" — join `gym_hours` to decide whether that's **closed** (expected,
render "Closed" with no percentage) or a **scraper gap** (a bug you want surfaced, not
smoothed over).

### 2.6 `gym_memberships`

Which gyms you belong to — drives the +15 boost and the dark pin ring.

| column       | type                                 | notes                               |
| ------------ | ------------------------------------ | ----------------------------------- |
| `user_id`    | `uuid`                               | FK → `profiles` `on delete cascade` |
| `gym_id`     | `bigint`                             | FK → `gyms` `on delete cascade`     |
| `created_at` | `timestamptz not null default now()` |                                     |
| PK           | `(user_id, gym_id)`                  |                                     |

**Per-gym rows, deliberately — despite most people holding a chain membership.** Nobody is a
"Dogpatch member"; they're a Touchstone member with access to four gyms (Movement, three). The
tempting move is a brand-level membership table. It's the wrong one: both chains also sell
single-gym and home-gym tiers, so per-gym rows are the _more general_ model — they express
chain-wide and single-gym membership alike, where a `brand` column can only express the first.
They also feed the ranking boost with a plain join, no brand resolution at query time.

A chain toggle is therefore a **Gyms-screen affordance** that expands to N slugs client-side.
No new API surface is needed: `PUT /api/me/memberships` already replaces the whole set in one
transaction.

### 2.7 `saved_locations`

Home + a couple of saved spots. `GET /api/rankings?location_id=` points here.

| column                   | type                                 | notes                                           |
| ------------------------ | ------------------------------------ | ----------------------------------------------- |
| `id`                     | `uuid PK default gen_random_uuid()`  | exposed to the client, so not sequential         |
| `user_id`                | `uuid`                               | FK → `profiles` `on delete cascade`             |
| `label`                  | `text not null`                      | "Home", "Office", "Ryan's"                      |
| `address`                | `text`                               | nullable; display only                          |
| `latitude` / `longitude` | `double precision not null`          | same checks as `gyms`                           |
| `geog`                   | `extensions.geography(Point,4326)`   | generated stored, same pattern as `gyms`        |
| `is_default`             | `boolean not null default false`     | which one the app opens on                      |
| `created_at`             | `timestamptz not null default now()` |                                                 |
| unique                   | `(user_id, label)`                   |                                                 |
| unique index             | `(user_id) where is_default`         | enforces at most one default per user in the DB |

**Promoting a default is a two-statement write.** Clear the old default, then set the new one,
in one transaction — otherwise the partial unique index raises a violation, which is exactly its
job. There's no deferred-constraint escape hatch: deferral applies to unique _constraints_, and
constraints can't be partial, so `where is_default` forces an index.

No GiST index — a user has ~3 of these and they're always fetched by `user_id`. The "small set"
cap from the plan is enforced in the API, not with a check constraint.

### 2.8 `ranking_prefs`

The configurable weights. Defaults are exactly the prototype formula, so an untouched account
scores identically to the mockup.

| column               | type                                 | default |
| -------------------- | ------------------------------------ | ------- |
| `user_id`            | `uuid` PK, FK → `profiles` cascade   |         |
| `w_crowd`            | `numeric(5,3) not null`              | `0.6`   |
| `w_travel`           | `numeric(5,3) not null`              | `0.5`   |
| `member_boost`       | `numeric(5,2) not null`              | `15`    |
| `closed_penalty`     | `numeric(5,2) not null`              | `60`    |
| `travel_cap_minutes` | `smallint not null`                  | `60`    |
| `updated_at`         | `timestamptz not null default now()` |         |

**Decision:** the row is written alongside the profile at bootstrap rather than left absent and
coalesced at read time — one code path, and the defaults stay in the DDL where they're visible.
The base 100 stays a constant in Python; it's a presentation offset, not a tunable.

### 2.9 `travel_times`

Mapbox Matrix cache. 3 locations × 16 gyms = 48 near-static pairs, refreshed on the order of weeks.

| column        | type                                 | notes                                                                                                                                             |
| ------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `location_id` | `uuid`                               | FK → `saved_locations` `on delete cascade`                                                                                                        |
| `gym_id`      | `bigint`                             | FK → `gyms` `on delete cascade`                                                                                                                   |
| `minutes`     | `numeric(6,2) not null`              |                                                                                                                                                   |
| `meters`      | `integer`                            | nullable                                                                                                                                          |
| `provider`    | `text not null default 'mapbox'`     | `check in ('mapbox','haversine_fallback')` — so a cached row from the `6 + miles × 2.3` fallback is visibly second-class and gets re-fetched first |
| `computed_at` | `timestamptz not null default now()` | age drives invalidation                                                                                                                           |
| PK            | `(location_id, gym_id)`              |                                                                                                                                                   |

**Decision:** keyed by `location_id`, so moving a saved location invalidates its rows by cascade.
The alternative — keying by rounded coordinates so the cache is shared across users — is better
at scale but pointless for a private app, and it leaks one user's locations into another's cache
lookups.

---

## 3. Where busyness comes from

**One scrape fills both tables.** A single page load returns the entire weekly curve _and_ the
live reading (126 elements: 125 hourly bars across all 7 days, plus 1 live label). There is no
separate "daily curve job" — every poll parses both, inserts one `busyness_snapshots` row, and
upserts the curve bars it saw.

**Google's forecast is the forecast.** We do not derive predictions from
`busyness_snapshots`; `busyness_curves` is the single prediction source for the time scrubber
and "best time to climb". Google aggregates far more traffic than sixteen gyms' worth of polling
ever will, and rebuilding that badly is not the point of this project.

**Known limit — the curve does not know about holidays.** Google's weekly histogram is a
_typical_ week keyed by day-of-week, not by date. On Memorial Day it still shows the ordinary
Monday curve. What reflects an unusual day is the **live** reading, which is today's actuals and
carries its own baseline (`"Currently 54% busy, usually 58% busy"`). So:

| feature                | source                        | holiday-aware? |
| ---------------------- | ----------------------------- | -------------- |
| Live busyness "now"    | `busyness_snapshots.live_pct` | yes            |
| Time scrubber (future) | `busyness_curves.busy_pct`    | no             |
| Best time to climb     | `busyness_curves.busy_pct`    | no             |

Nothing to fix in the schema — but the forecast is a typical-week forecast, and the UI shouldn't
promise more than that. The `live_pct` vs `typical_pct` gap in the snapshots is the cheap signal
for "today is not a normal day", available for free if it's ever worth surfacing.

**Live wins for "now"; the curve is only consulted for future hours.** If `live_pct` exists for
the current hour, show it and ignore what the curve says — the curve is a typical-week aggregate
and live is today. This rule matters more than it looks: it means a disagreement between Google's
rendered hours and our `gym_hours` cannot affect the current-moment display at all.

**`gym_hours` is authoritative for open/closed; the curve is authoritative for busyness inside
those hours.** Resolving a future hour `H` at gym `G` runs in that order:

1. `gym_hours` says `G` is closed at `H` → **"Closed"**, whatever the curve holds.
2. A curve row exists for `(G, dow, H)` → **show it**, including a row Google has since stopped
   rendering (see below).
3. Otherwise → **"no forecast for this hour"**, explicitly, not a zero.

**Assumption: Google's window covers ours.** Google is taken to render bars for at least every
hour `gym_hours` calls open, and possibly more. Under that assumption only one mismatch direction
occurs in practice:

| mismatch                                       | resolution                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| Google's bars **run past** our closing time    | step 1 — clamped to `gym_hours`; the extra bars are stored but never shown  |
| Google's bars **stop before** our closing time | assumed not to happen; if it does, step 2 then step 3 degrade gracefully    |

This is why there's no hours reconciliation job: the assumption costs nothing to hold, and being
wrong about it surfaces as an explicit "no forecast for this hour" rather than as bad data.

Step 2 works only because the upsert never deletes: the stored curve is a union over time, so an
hour Google stopped rendering keeps its last known value with a stale `updated_at`. That is the
practical reason behind the never-delete-then-insert rule above, not just tidiness.

Out-of-hours bars are still **stored**, deliberately, even though step 1 hides them — filtering
them at write time would throw away the only evidence that the assumption above is wrong.

Step 3 is also why closed hours are left as missing rows rather than zeros: a stored `0` would be
indistinguishable from a genuinely empty gym, and step 2 could then serve it as a forecast.

**Known consequence for "best time to climb".** It scans future open hours for the minimum, and
an hour with no curve row has no value to compare, so it can never be recommended. If Google's
bars stop before our seeded closing time, that final hour is permanently ineligible. Acceptable —
few people want a session starting at 22:45 — but it's a behavior to know about rather than
rediscover.

---

## 4. Cross-cutting decisions

**Row Level Security — on, with zero policies, on every table.**
The Supabase anon key ships inside the app bundle, so PostgREST is publicly reachable whether or
not we use it. FastAPI connects as the table owner and bypasses RLS, so a deny-by-default posture
costs us nothing and closes the whole PostgREST surface:

```sql
alter table public.<t> enable row level security;
revoke all on public.<t> from anon, authenticated;
```

This is what keeps "Supabase provides Auth only" true in practice rather than by convention.

**Spatial queries: `ST_DWithin`, never `ST_Distance <= x`.** Only `ST_DWithin(a, b, meters)` uses
`gyms_geog_idx`; a bare `ST_Distance(...) <= x` sequential-scans and computes a distance per row.
At n=16 neither is slow, but the pre-filter is the entire reason that index exists. Geography
distances are in **meters** — miles are `meters / 1609.344`.

**Alembic fights the generated column, and this is settled.** Autogenerate compares
server-side `Computed()` expressions poorly and geoalchemy2 compounds it by creating spatial
indexes as a side effect. `alembic/env.py` carries an `include_object` hook excluding both
`geog` columns and `gyms_geog_idx`, and the spatial parts of the initial migration are
hand-written. geoalchemy2 is a backend dependency as of that work.

One caveat found in practice: the hook is **not** consulted for columns of a brand-new table —
Alembic inlines those into `create_table` — so a from-scratch regeneration still needs the
`geog` columns stripped by hand.

**Alembic and the `auth` schema.** Autogenerate is restricted to `public`, so it can't see
`auth.users` and won't emit the `profiles.id` foreign key. That FK is hand-written into the
migration *and* excluded by the same `include_object` hook: once it exists in the database but
not on the model, every later autogenerate reads it as a constraint you deleted and proposes
`drop_constraint`, which would sever profiles from Supabase Auth.

**PostGIS types are in `extensions`.** Model columns must be declared as
`extensions.geography(Point,4326)`, matching the existing `enable_postgis` migration, or Alembic
will try to create the type in `public`.

**Timestamps.** `timestamptz` throughout; `gym_hours.opens_at`/`closes_at` are naked `time`
values interpreted in the gym's own `timezone`. Postgres has no `ON UPDATE` clause, so
`updated_at` is **not** self-maintaining: it's set by SQLAlchemy `onupdate=func.now()`, matching
the Python-over-DB-triggers choice made for profile bootstrapping. Caveat — `onupdate` doesn't
fire for Core bulk updates or raw SQL, which is acceptable only because FastAPI is the single
writer.

**Slugs at the boundary.** The API speaks slugs; the database speaks `gym_id`. Resolution
happens once, at the edge of the request — no handler should be joining on `slug`.

---

## 5. Deliberately not included

- **No `climbs` / session log.** Nothing in v1 records that you went.
- **No gym capacity / occupancy counts.** Redpoint HQ exposes none; percent-busy is all we get.
- **No reviews, notes, or favorites** beyond membership.
- **No device / push token table.** No notifications in v1.
- **No usage-based clustering weight.** Deferred to v2 per the plan; clustering priority is
  membership-only, which `gym_memberships` already answers.
- **No holiday calendar.** See §3 — Google's curve wouldn't use it, and overriding Google's
  forecast with our own holiday adjustment is exactly the DIY prediction this project declined.
- **No brand-level membership table.** See §2.6 — per-gym rows already express chain memberships
  and single-gym tiers; a brand column expresses only the first.
- **No `latest_busy_pct` cache columns on `gyms`.** Considered and rejected. The read it would
  optimize is sixteen index descents that don't degrade with table growth (§2.4), and the cost is
  real: two writers of the same fact that can silently diverge, hot-updated columns on the
  otherwise-static table the API caches hardest, and the collapse of the reference-vs-observed
  split this schema is organized around. If that read ever does get hot, the answer is a
  16-row `gym_busyness_current` table or a matview — not mutable state on `gyms`.

---

## 6. Resolved decisions

1. **`gym_hours` stays a separate table.** 112 seed rows, correct on day one when a gym changes
   its weekend hours.
2. **Surrogate `bigint` id on `gyms`, `slug` kept as a unique natural key.** Both, not either —
   the slug remains the public identifier and nothing references it. See §2.2.
3. **Google's curve is the only forecast source.** One scrape yields both the curve and the live
   reading. `busyness_snapshots` is owned data and observability, not a prediction input. Caveat
   on holidays recorded in §3.
4. **0 = Sunday**, matching Postgres `extract(dow)`; the app subtracts 1 from `Calendar.weekday`.
5. **Seed ships as a migration**, so a fresh Supabase project comes up complete; a Python script
   handles later corrections once hours, rates, and waiver links get their real verification pass.
6. **Poll cadence: 30 minutes**, open hours only. ~151k snapshot rows/year, and ~30% fewer
   Playwright runs than polling around the clock. Easy to tighten to 15 min later if the evening
   swing turns out to be under-sampled.
7. **No retention policy.** Every poll is kept, append-only. Revisit only if the scrape ever
   expands well beyond sixteen venues.
8. **Missing curve rows stay missing.** Closed hours are not zero-filled; `gym_hours` supplies
   the closed/gap distinction (§3).
9. **Polling is gated on `gym_hours`** — only currently-open gyms are scraped.
10. **Hours disagreements resolve by rule, not by picking a winner.** `gym_hours` bounds what is
    displayable; the curve fills it, falling back to the last value Google rendered, then to an
    explicit "no forecast". See §3.
11. **No hours reconciliation job.** Google's forecast window is assumed to cover `gym_hours`.
    The rules in §3 degrade gracefully if that's ever wrong, which is what makes the assumption
    safe to hold.
12. **The Studio runs the 3pm tier at its own prices** — $25 before, $30 after. Verified manually.
13. **The sixteen `google_maps_query` strings resolve to the right venues.** Each was searched
    in Google Maps by hand and confirmed. This was the last silent-failure risk in the seed — a
    wrong match returns a perfectly valid curve for the wrong business — so re-verify any string
    that is ever edited, and have the first scraper run print the resolved place name anyway.

---

## 7. Outstanding data work

The seed is applied (§8) and its data is verified (§6.12, §6.13). Nothing here blocks the
backend; what remains is one app-side rendering decision and some optional polish.

**Not a database column:**

- **Logo assets — sourced and shipped.** All sixteen gyms resolve, from twelve files: ten
  per-gym marks plus two brand-level fallbacks, `logo-movement` covering the four Movement
  locations and `logo-benchmark` the two Benchmark ones. They live in
  `app/BoulderBay/Assets.xcassets` as imagesets named `logo-<slug>`, so the lookup is
  `Image("logo-\(gym.slug)")` falling back to `Image("logo-\(gym.brand)")` — the two fallback
  names are the `brand` column's values verbatim, so no mapping table is needed. Source URLs are
  still not stored: hot-linking gym WordPress uploads would break on their next re-upload and
  leak user IPs. The unprocessed masters stage in a gitignored `/logos`; the catalog is the
  committed copy.

  Both problems the raw files had are resolved. They are mark-only silhouettes (wordmarks
  cropped — except The Peak of Fremont, which keeps its trademark), black-on-transparent where
  they were white, with Movement's teal and Mosaic's orange preserved. Every file is normalised
  onto a 512×512 transparent canvas with the mark at 80% inset, so the three aspect ratios read
  at the same optical size in the square chip the Rankings rows and the gym detail header use.

  **One placement still needs handling:** black marks vanish against the `#1F5C42` best-pick
  card exactly as the white ones vanished against chalk. The fix is `.renderingMode(.template)`
  with a light tint on that card alone — the alpha channel carries the whole mark, so it costs
  no second asset.

**Optional, non-blocking:**

- `google_maps_url` for all 16 — a scraper latency and reliability win, and when present it
  doubles as the user-facing Google Maps link (a real place page rather than a coordinate
  search). Coordinates are the fallback, so nothing depends on it.
- A staleness bound on curve rows. Step 2 of §3 serves the last value Google rendered however
  old; `updated_at` already records the age if that's ever wanted.

**Map links are not stored, deliberately.** Apple Maps opens from `MKMapItem` built on
`latitude`/`longitude`; Google Maps opens from the universal link
`https://www.google.com/maps/search/?api=1&query=<lat>,<lng>`, which avoids the
`comgooglemaps://` scheme and its `LSApplicationQueriesSchemes` entry in `project.yml`. Storing
either URL would duplicate the coordinates in a second, rottable form — and coordinates are more
precise than geocoding a street address. `address` is display text, not a link source.

---

## 8. Where this lives in code

This document is the design record. What runs is Alembic, generated from
`backend/app/db/models.py`, in two applied revisions:

| revision | contents |
|---|---|
| `7bea7599f868` | the nine tables, constraints, indexes, and the RLS block |
| `b00fd69a53b6` | the sixteen gyms and their 112 `gym_hours` rows |

The hosted database is at `b00fd69a53b6`.

**There is deliberately no standalone `.sql` copy of the schema.** One existed while this was
being designed and was deleted once the models landed: a second representation that nothing
executes drifts from the one that does, silently, and the drift is only ever found by hand. To
read the DDL, generate it from what actually runs:

```bash
uv run alembic upgrade head --sql   # from an empty database
pg_dump --schema-only               # from the live one
```

`backend/tests/test_models.py` is what holds the models to this document: it asserts the table
set, every check-constraint name, and that both `geog` columns stay stored generated columns
carrying no implicit spatial index.

Four parts of the core revision are hand-written because autogenerate cannot emit them: the
two `geog` generated columns, `gyms_geog_idx`, the `profiles.id → auth.users(id)` foreign key,
and the RLS enable/revoke block (see §4). Three of those are also filtered out of autogenerate
by `include_object` in `alembic/env.py` — without that filter each run proposes dropping and
re-adding them, and in the FK's case would sever `profiles` from Supabase Auth.

Changing the schema means changing the models and generating a revision from them. Creating a
table out-of-band, while the models stayed empty, would leave the next
`alembic revision --autogenerate` emitting `DROP TABLE` for all nine.
