-- Boulder Bay — core schema + seed (v1)
--
-- Design and rationale: boulder_bay_schema.md
-- Requires:  PostGIS installed in `extensions`
--            (supabase/migrations/20260907072340_enable_postgis.sql)
--
-- NOT THE MIGRATION -- the human-readable reference for it. Alembic owns application
-- tables (see README § Database) and generates them from backend/app/db/models.py.
-- Part 1 landed as revision 7bea7599f868, Part 2 as b00fd69a53b6; both are applied.
-- Change the models, not this file, when the schema changes.
--
-- Conventions: 0 = Sunday (matches extract(dow)); percentages are 0-100 smallints;
-- money is integer cents; all times are the gym's local clock time, interpreted in
-- gyms.timezone.
--
-- updated_at columns are NOT self-maintaining -- Postgres has no ON UPDATE clause.
-- They are set by SQLAlchemy `onupdate=func.now()`, matching the same
-- Python-over-DB-triggers choice made for profile bootstrapping. Note that
-- `onupdate` does not fire for Core bulk updates or raw SQL; acceptable here
-- because FastAPI is the only writer.


-- ############################################################################
-- PART 1 — CORE SCHEMA
-- ############################################################################

begin;

-- ---------------------------------------------------------------- profiles --
-- Mirrors auth.users so the rest of the schema has a real FK target in public.
-- Rows are created lazily by FastAPI on first authenticated request, not by a
-- trigger on auth.users.

create table public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);


-- -------------------------------------------------------------------- gyms --
-- Surrogate bigint PK; `slug` is the public identifier (routes, seed data,
-- app-bundle logo assets) but nothing references it.

create table public.gyms (
    id                bigint generated always as identity primary key,
    slug              text not null unique,
    name              text not null,
    brand             text not null,
    city              text not null,
    address           text,                    -- NULL until the verification pass; see Part 2
    latitude          double precision not null,
    longitude         double precision not null,
    geog              extensions.geography(Point, 4326)
                          generated always as (
                              extensions.geography(
                                  extensions.st_setsrid(
                                      extensions.st_makepoint(longitude, latitude),
                                      4326))
                          ) stored,
    timezone          text not null default 'America/Los_Angeles',
    google_maps_query text not null,           -- search string the scraper falls back to
    google_maps_url   text,                    -- canonical /maps/place/ URL; preferred, skips search
                                               -- disambiguation. NULL until verified per gym.
    website_url       text,
    waiver_url        text,
    -- Day-rate tiering: Touchstone charges $30 before 3pm and $35 after. Both peak
    -- columns are NULL for a gym with one flat day rate, which is most of them.
    -- `peak_starts_at` is local clock time, interpreted in `timezone` like gym_hours.
    day_pass_cents      integer,               -- base / off-peak
    day_pass_peak_cents integer,
    peak_starts_at      time,
    monthly_cents     integer,
    is_active         boolean not null default true,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),

    constraint gyms_slug_format      check (slug ~ '^[a-z0-9-]+$'),
    constraint gyms_brand_valid      check (brand in ('movement', 'touchstone', 'benchmark',
                                                     'independent')),
    constraint gyms_latitude_range   check (latitude between -90 and 90),
    constraint gyms_longitude_range  check (longitude between -180 and 180),
    constraint gyms_day_pass_nonneg  check (day_pass_cents >= 0),
    constraint gyms_peak_pass_nonneg check (day_pass_peak_cents >= 0),
    constraint gyms_monthly_nonneg   check (monthly_cents >= 0),
    -- Half a tier is always a bug: a peak price with no start time (or the reverse)
    -- cannot be rendered. num_nulls() counts NULLs among its arguments.
    constraint gyms_peak_rate_complete
        check (num_nulls(day_pass_peak_cents, peak_starts_at) <> 1)
);

-- Backs the straight-line pre-filter that narrows candidates before Mapbox is called.
-- Query it with extensions.st_dwithin(g.geog, :loc, :meters) -- st_distance(...) <= x does
-- NOT use this index, it seq-scans. geography distances are METERS (miles = m / 1609.344).
create index gyms_geog_idx on public.gyms using gist (geog);


-- --------------------------------------------------------------- gym_hours --
-- Feeds three things: the detail screen, the closed-gym ranking penalty, and
-- "best time to climb" (the future *open* hour with the lowest predicted busyness).

create table public.gym_hours (
    gym_id      bigint   not null references public.gyms (id) on delete cascade,
    day_of_week smallint not null,
    opens_at    time     not null,
    closes_at   time     not null,

    primary key (gym_id, day_of_week),
    constraint gym_hours_day_range check (day_of_week between 0 and 6),
    -- Past-midnight closing is rejected for v1: no seed gym does it, and allowing
    -- it forces every "is it open now" query to branch.
    constraint gym_hours_ordered   check (closes_at > opens_at)
);


-- -------------------------------------------------------- busyness_snapshots --
-- The time series we own. One row per gym per poll (30 min, open hours only).
-- Observability and drift measurement — NOT a prediction input; forecasts come
-- from busyness_curves.

create table public.busyness_snapshots (
    id          bigint generated always as identity primary key,
    gym_id      bigint      not null references public.gyms (id) on delete cascade,
    observed_at timestamptz not null,          -- the poll tick, not now()
    live_pct    smallint,                      -- NULL when Google reports no live reading
    typical_pct smallint,                      -- the "usually N% busy" half of the same label
    source      text        not null default 'google_maps',

    -- Makes a re-run of a poll idempotent. This index also serves the
    -- "latest reading per gym" read (scanned backwards), so there is no second index.
    constraint busyness_snapshots_tick_unique   unique (gym_id, observed_at),
    constraint busyness_snapshots_live_range    check (live_pct between 0 and 100),
    constraint busyness_snapshots_typical_range check (typical_pct between 0 and 100)
);


-- ----------------------------------------------------------- busyness_curves --
-- Google's typical-week histogram; the single source for the time scrubber and
-- "best time to climb". Refreshed by upsert on every poll.
--
-- NOTE: a scrape never contains the current hour's bar (that element carries the
-- live label instead), so upsert the 125 bars you got and leave the current hour's
-- stored row alone. Never delete-then-insert, or you punch an hourly hole each run.
--
-- CLOSED HOURS HAVE NO ROW. Google renders ~18 bars/day, so hours 0-5 are simply
-- absent. Do NOT seed them as busy_pct = 0 -- that is indistinguishable from a
-- genuinely empty gym and destroys the only signal there is. A missing row means
-- "no data"; join gym_hours to decide whether that is "closed" (expected) or a
-- scraper gap (a bug you want to see).

create table public.busyness_curves (
    gym_id      bigint      not null references public.gyms (id) on delete cascade,
    day_of_week smallint    not null,
    hour_of_day smallint    not null,
    busy_pct    smallint    not null,
    updated_at  timestamptz not null default now(),   -- last time Google confirmed this bar

    primary key (gym_id, day_of_week, hour_of_day),
    constraint busyness_curves_day_range  check (day_of_week between 0 and 6),
    constraint busyness_curves_hour_range check (hour_of_day between 0 and 23),
    constraint busyness_curves_pct_range  check (busy_pct between 0 and 100)
);


-- --------------------------------------------------------- gym_memberships --
-- Drives the ranking boost and the dark pin ring on the map.
--
-- Per-gym rows, deliberately, even though most people hold a chain membership
-- (Touchstone = 4 gyms, Movement = 3). Both chains also sell single-gym and
-- home-gym tiers, so per-gym rows are the MORE general model -- a brand column
-- could not express them. A chain toggle is a Gyms-screen affordance that expands
-- to N slugs client-side; PUT /api/me/memberships already replaces the whole set
-- in one transaction, so no bulk endpoint is needed.

create table public.gym_memberships (
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    gym_id     bigint      not null references public.gyms (id) on delete cascade,
    created_at timestamptz not null default now(),

    primary key (user_id, gym_id)
);


-- ---------------------------------------------------------- saved_locations --
-- uuid PK because the id is handed to the client in GET /api/rankings?location_id=
-- and shouldn't be enumerable.

create table public.saved_locations (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid             not null references public.profiles (id) on delete cascade,
    label      text             not null,
    address    text,
    latitude   double precision not null,
    longitude  double precision not null,
    geog       extensions.geography(Point, 4326)
                   generated always as (
                       extensions.geography(
                           extensions.st_setsrid(
                               extensions.st_makepoint(longitude, latitude),
                               4326))
                   ) stored,
    is_default boolean     not null default false,
    created_at timestamptz not null default now(),

    constraint saved_locations_label_unique    unique (user_id, label),
    constraint saved_locations_latitude_range  check (latitude between -90 and 90),
    constraint saved_locations_longitude_range check (longitude between -180 and 180)
);

create index saved_locations_user_idx on public.saved_locations (user_id);

-- At most one default per user, enforced in the database rather than the API.
-- Promoting a new default must clear the old one first, in the same transaction:
--     update saved_locations set is_default = false where user_id = :uid;
-- There is no deferred-constraint escape hatch -- deferral works on unique
-- CONSTRAINTS, and constraints cannot be partial, so `where is_default` forces
-- an index.
create unique index saved_locations_one_default_idx
    on public.saved_locations (user_id)
    where is_default;

-- No GiST index: a user has ~3 of these and they are always fetched by user_id.


-- ------------------------------------------------------------ ranking_prefs --
-- Defaults are exactly the prototype formula, so an untouched account scores
-- identically to the mockup. The base 100 stays a constant in Python — it's a
-- presentation offset, not a tunable.

create table public.ranking_prefs (
    user_id            uuid primary key references public.profiles (id) on delete cascade,
    w_crowd            numeric(5, 3) not null default 0.6,
    w_travel           numeric(5, 3) not null default 0.5,
    member_boost       numeric(5, 2) not null default 15,
    closed_penalty     numeric(5, 2) not null default 60,
    travel_cap_minutes smallint      not null default 60,
    updated_at         timestamptz   not null default now(),

    constraint ranking_prefs_travel_cap_positive check (travel_cap_minutes > 0)
);


-- ------------------------------------------------------------- travel_times --
-- Mapbox Matrix cache: 3 locations x 16 gyms = 48 near-static pairs, refreshed on
-- the order of weeks. Keyed by location_id so moving a location invalidates by cascade.

create table public.travel_times (
    location_id uuid          not null references public.saved_locations (id) on delete cascade,
    gym_id      bigint        not null references public.gyms (id) on delete cascade,
    minutes     numeric(6, 2) not null,
    meters      integer,
    provider    text          not null default 'mapbox',
    computed_at timestamptz   not null default now(),

    primary key (location_id, gym_id),
    -- A row from the `6 + miles * 2.3` fallback is visibly second-class and gets re-fetched first.
    constraint travel_times_provider_valid  check (provider in ('mapbox', 'haversine_fallback')),
    constraint travel_times_minutes_nonneg  check (minutes >= 0),
    constraint travel_times_meters_nonneg   check (meters >= 0)
);


-- ------------------------------------------------------ row level security --
-- The Supabase anon key ships inside the app bundle, so PostgREST is publicly
-- reachable whether or not we use it. FastAPI connects as the table owner and
-- bypasses RLS, so deny-by-default costs us nothing and closes that whole surface.
-- Enabled with ZERO policies, deliberately.

alter table public.profiles           enable row level security;
alter table public.gyms               enable row level security;
alter table public.gym_hours          enable row level security;
alter table public.busyness_snapshots enable row level security;
alter table public.busyness_curves    enable row level security;
alter table public.gym_memberships    enable row level security;
alter table public.saved_locations    enable row level security;
alter table public.ranking_prefs      enable row level security;
alter table public.travel_times       enable row level security;

-- Supabase's default privileges grant these roles access to new tables in public.
revoke all on public.profiles           from anon, authenticated;
revoke all on public.gyms               from anon, authenticated;
revoke all on public.gym_hours          from anon, authenticated;
revoke all on public.busyness_snapshots from anon, authenticated;
revoke all on public.busyness_curves    from anon, authenticated;
revoke all on public.gym_memberships    from anon, authenticated;
revoke all on public.saved_locations    from anon, authenticated;
revoke all on public.ranking_prefs      from anon, authenticated;
revoke all on public.travel_times       from anon, authenticated;

commit;


-- ############################################################################
-- PART 2 — SEED (the sixteen curated gyms)
-- ############################################################################
--
-- Names, brands, cities, coordinates, rates and hours are all hand-verified, and this
-- block is their source of truth. It supersedes both the nine-gym table in
-- boulder_bay_plan.md and the original hand-collected intake file, which was explicitly
-- best-effort, drifted behind this seed, and has been deleted.
--
-- Slugs reuse the plan's originals wherever the gym survived (mv-belmont, mv-sf,
-- dogpatch, mission, ironworks, pipe, studio); the nine additions follow the same
-- shape — chain prefix for multi-location chains, bare name for one-offs.
--
-- `address`, `website_url` and `waiver_url` are filled in and hand-verified for all
-- sixteen. `google_maps_url` is the one column still NULL throughout, deliberately:
-- nothing may be invented here. A fabricated street address would sit behind the
-- detail screen's "open in Apple Maps" tap, so the app falls back to latitude/
-- longitude. Backfill `google_maps_url` with each resolved /maps/place/ link once
-- the scraper has confirmed all sixteen, so later runs skip search.

begin;

insert into public.gyms
    (slug, name, brand, city, latitude, longitude, google_maps_query,
     address, website_url, waiver_url,
     day_pass_cents, day_pass_peak_cents, peak_starts_at, monthly_cents)
values
    -- Touchstone: $30 before 3pm, $35 after.
    ('mission', 'Mission Cliffs', 'touchstone', 'San Francisco',
     37.7609801, -122.4150888, 'Mission Cliffs',
     '2295 Harrison St, San Francisco, CA 94110',
     'https://touchstoneclimbing.com/mission-cliffs/',
     'https://touchstone.rphq.com/missioncliffs/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('dogpatch', 'Dogpatch Boulders', 'touchstone', 'San Francisco',
     37.7567054, -122.3903193, 'Dogpatch Boulders',
     '2573 3rd St, San Francisco, CA 94107',
     'https://touchstoneclimbing.com/dogpatch-boulders/',
     'https://touchstone.rphq.com/dogpatch/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('hyperion', 'Hyperion Climbing', 'touchstone', 'Redwood City',
     37.4842893, -122.217014, 'Hyperion Climbing',
     '801 Willow St, Redwood City, CA 94063',
     'https://touchstoneclimbing.com/hyperion/',
     'https://portal.touchstoneclimbing.com/hyperion/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('gwpc', 'Great Western Power Company', 'touchstone', 'Oakland',
     37.8098428, -122.2727291, 'Great Western Power Company',
     '520 20th St, Oakland, CA 94612',
     'https://touchstoneclimbing.com/gwpower-co/',
     'https://touchstone.rphq.com/power/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('pipe', 'Pacific Pipe', 'touchstone', 'Oakland',
     37.8156325, -122.2913122, 'Pacific Pipe',
     '2140 Mandela Pkwy, Oakland, CA 94607',
     'https://touchstoneclimbing.com/pacific-pipe/',
     'https://touchstone.rphq.com/pacificpipe/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('ironworks', 'Berkeley Ironworks', 'touchstone', 'Berkeley',
     37.8509776, -122.2951509, 'Berkeley Ironworks',
     '800 Potter St, Berkeley, CA 94710',
     'https://touchstoneclimbing.com/ironworks/',
     'https://touchstone.rphq.com/ironworks/agreements/waiver',
     3000, 3500, time '15:00', 13000),
    ('the-oaks', 'The Oaks Climbing', 'touchstone', 'Berkeley',
     37.8915899, -122.2806575, 'The Oaks Climbing',
     '1875 Solano Ave, Berkeley, CA 94707',
     'https://touchstoneclimbing.com/the-oaks/',
     'https://portal.touchstoneclimbing.com/oaks/agreements/waiver',
     3000, 3500, time '15:00', 13000),

    -- Studio is Touchstone, but cheaper: $25 before 3pm, $30 after.
    -- website_url is the chain portal's landing page for this gym, not a
    -- touchstoneclimbing.com/<gym>/ page like the other seven. Verified, just inconsistent.
    ('studio', 'The Studio Climbing', 'touchstone', 'San Jose',
     37.330216, -121.8885325, 'The Studio Climbing',
     '396 S 1st St, San Jose, CA 95113',
     'https://portal.touchstoneclimbing.com/studio',
     'https://portal.touchstoneclimbing.com/studio/agreements/waiver',
     2500, 3000, time '15:00', 11200),

    -- Movement: flat day rate, monthly varies by location.
    ('mv-sf', 'Movement San Francisco', 'movement', 'San Francisco',
     37.8041752, -122.4707639, 'Movement San Francisco',
     '924 Mason St, San Francisco, CA 94129',
     'https://movementgyms.com/san-francisco/',
     'https://portal.movementgyms.com/san-francisco/agreements/participant-agreement',
     3300, null, null, 11500),
    ('mv-belmont', 'Movement Belmont', 'movement', 'Belmont',
     37.5289862, -122.2900729, 'Movement Belmont',
     '100 El Camino Real, Belmont, CA 94002',
     'https://movementgyms.com/belmont/',
     'https://portal.movementgyms.com/belmont/agreements/participant-agreement',
     3300, null, null, 11400),
    ('mv-mountain-view', 'Movement Mountain View', 'movement', 'Mountain View',
     37.4028887, -122.1163429, 'Movement Mountain View',
     '630 San Antonio Rd, Mountain View, CA 94040',
     'https://movementgyms.com/mountain-view',
     'https://portal.movementgyms.com/mountain-view/agreements/participant-agreement',
     3300, null, null, 12100),
    ('mv-santa-clara', 'Movement Santa Clara', 'movement', 'Santa Clara',
     37.3667359, -121.9505707, 'Movement Santa Clara',
     '801 Martin Ave, Santa Clara, CA 95050',
     'https://movementgyms.com/santa-clara/',
     'https://portal.movementgyms.com/santa-clara/agreements/participant-agreement',
     3300, null, null, 12100),

    -- Benchmark: two locations sharing one website and one waiver portal. Both are
    -- named just "Benchmark", so any list UI must render `city` alongside `name`.
    -- The map queries are city-qualified because a bare "Benchmark Climbing"
    -- cannot distinguish them for the scraper.
    ('bm-sf', 'Benchmark San Francisco', 'benchmark', 'San Francisco',
     37.7888786, -122.4242155, 'Benchmark Climbing San Francisco',
     '1414 Van Ness Ave, San Francisco, CA 94109',
     'https://www.benchmarkclimbing.com/',
     'https://benchmark.portal.approach.app/profile/sign-waiver',
     3000, null, null, 9900),
    ('bm-berkeley', 'Benchmark Berkeley', 'benchmark', 'Berkeley',
     37.8781104, -122.2712743, 'Benchmark Climbing Berkeley',
     '1607 Shattuck Ave., Berkeley, CA 94709',
     'https://www.benchmarkclimbing.com/',
     'https://benchmark.portal.approach.app/profile/sign-waiver',
     3000, null, null, 9900),

    -- Independents.
    ('the-peak', 'The Peak of Fremont', 'independent', 'Fremont',
     37.5105982, -121.9535299, 'The Peak of Fremont',
     '4020 Technology Pl Suite 1, Fremont, CA 94538',
     'https://thepeakoffremont.com/',
     'https://thepeakoffremont.com/the-peak-of-fremont-waiver/',
     3000, null, null, 7200),
    ('mosaic', 'Mosaic Boulders', 'independent', 'Berkeley',
     37.8674946, -122.2613914, 'Mosaic Boulders',
     '2369 Telegraph Ave, Berkeley, CA 94704',
     'https://www.mosaicboulders.com/',
     'https://mosaic.portal.approach.app/waiver',
     2200, null, null, 7500)
on conflict (slug) do nothing;


-- Hours: 0 = Sunday. Transcribed per-gym rather than pattern-generated, because the
-- patterns don't hold — Movement closes at 18:00 Sunday but 20:00 Saturday, and
-- Dogpatch and Pacific Pipe run an hour later on Tuesdays and Thursdays only.
-- Kept one gym per comment block so a single gym's week is reviewable in isolation.
insert into public.gym_hours (gym_id, day_of_week, opens_at, closes_at)
select g.id, h.day_of_week, h.opens_at, h.closes_at
from (values
    -- Benchmark San Francisco
    ('bm-sf', 0, time '10:00', time '19:00'), ('bm-sf', 1, time '11:00', time '22:00'),
    ('bm-sf', 2, time '11:00', time '22:00'), ('bm-sf', 3, time '11:00', time '22:00'),
    ('bm-sf', 4, time '11:00', time '22:00'), ('bm-sf', 5, time '11:00', time '22:00'),
    ('bm-sf', 6, time '10:00', time '19:00'),
    -- Benchmark Berkeley
    ('bm-berkeley', 0, time '10:00', time '19:00'), ('bm-berkeley', 1, time '07:00', time '22:00'),
    ('bm-berkeley', 2, time '07:00', time '22:00'), ('bm-berkeley', 3, time '07:00', time '22:00'),
    ('bm-berkeley', 4, time '07:00', time '22:00'), ('bm-berkeley', 5, time '07:00', time '22:00'),
    ('bm-berkeley', 6, time '10:00', time '19:00'),
    -- Mission Cliffs
    ('mission', 0, time '09:00', time '19:00'), ('mission', 1, time '06:00', time '22:00'),
    ('mission', 2, time '06:00', time '22:00'), ('mission', 3, time '06:00', time '22:00'),
    ('mission', 4, time '06:00', time '22:00'), ('mission', 5, time '06:00', time '22:00'),
    ('mission', 6, time '09:00', time '19:00'),
    -- Dogpatch Boulders (later Tue/Thu)
    ('dogpatch', 0, time '10:00', time '19:00'), ('dogpatch', 1, time '07:00', time '22:00'),
    ('dogpatch', 2, time '07:00', time '23:00'), ('dogpatch', 3, time '07:00', time '22:00'),
    ('dogpatch', 4, time '07:00', time '23:00'), ('dogpatch', 5, time '07:00', time '22:00'),
    ('dogpatch', 6, time '10:00', time '19:00'),
    -- Movement San Francisco
    ('mv-sf', 0, time '08:00', time '18:00'), ('mv-sf', 1, time '06:00', time '23:00'),
    ('mv-sf', 2, time '06:00', time '23:00'), ('mv-sf', 3, time '06:00', time '23:00'),
    ('mv-sf', 4, time '06:00', time '23:00'), ('mv-sf', 5, time '06:00', time '23:00'),
    ('mv-sf', 6, time '08:00', time '20:00'),
    -- Movement Belmont
    ('mv-belmont', 0, time '08:00', time '18:00'), ('mv-belmont', 1, time '06:00', time '23:00'),
    ('mv-belmont', 2, time '06:00', time '23:00'), ('mv-belmont', 3, time '06:00', time '23:00'),
    ('mv-belmont', 4, time '06:00', time '23:00'), ('mv-belmont', 5, time '06:00', time '23:00'),
    ('mv-belmont', 6, time '08:00', time '20:00'),
    -- Hyperion Climbing
    ('hyperion', 0, time '10:00', time '18:00'), ('hyperion', 1, time '10:00', time '22:00'),
    ('hyperion', 2, time '10:00', time '22:00'), ('hyperion', 3, time '10:00', time '22:00'),
    ('hyperion', 4, time '10:00', time '22:00'), ('hyperion', 5, time '10:00', time '22:00'),
    ('hyperion', 6, time '10:00', time '18:00'),
    -- Movement Mountain View
    ('mv-mountain-view', 0, time '08:00', time '18:00'),
    ('mv-mountain-view', 1, time '06:00', time '23:00'),
    ('mv-mountain-view', 2, time '06:00', time '23:00'),
    ('mv-mountain-view', 3, time '06:00', time '23:00'),
    ('mv-mountain-view', 4, time '06:00', time '23:00'),
    ('mv-mountain-view', 5, time '06:00', time '23:00'),
    ('mv-mountain-view', 6, time '08:00', time '20:00'),
    -- Movement Santa Clara
    ('mv-santa-clara', 0, time '08:00', time '18:00'),
    ('mv-santa-clara', 1, time '06:00', time '23:00'),
    ('mv-santa-clara', 2, time '06:00', time '23:00'),
    ('mv-santa-clara', 3, time '06:00', time '23:00'),
    ('mv-santa-clara', 4, time '06:00', time '23:00'),
    ('mv-santa-clara', 5, time '06:00', time '23:00'),
    ('mv-santa-clara', 6, time '08:00', time '20:00'),
    -- The Studio Climbing
    ('studio', 0, time '10:00', time '17:00'), ('studio', 1, time '10:00', time '22:00'),
    ('studio', 2, time '10:00', time '22:00'), ('studio', 3, time '10:00', time '22:00'),
    ('studio', 4, time '10:00', time '22:00'), ('studio', 5, time '10:00', time '22:00'),
    ('studio', 6, time '10:00', time '17:00'),
    -- The Peak of Fremont
    ('the-peak', 0, time '10:00', time '18:00'), ('the-peak', 1, time '12:00', time '22:00'),
    ('the-peak', 2, time '12:00', time '22:00'), ('the-peak', 3, time '12:00', time '22:00'),
    ('the-peak', 4, time '12:00', time '22:00'), ('the-peak', 5, time '12:00', time '22:00'),
    ('the-peak', 6, time '10:00', time '18:00'),
    -- Great Western Power Company
    ('gwpc', 0, time '09:00', time '16:00'), ('gwpc', 1, time '06:00', time '22:00'),
    ('gwpc', 2, time '06:00', time '22:00'), ('gwpc', 3, time '06:00', time '22:00'),
    ('gwpc', 4, time '06:00', time '22:00'), ('gwpc', 5, time '06:00', time '22:00'),
    ('gwpc', 6, time '09:00', time '16:00'),
    -- Pacific Pipe (later Tue/Thu)
    ('pipe', 0, time '10:00', time '19:00'), ('pipe', 1, time '07:00', time '22:00'),
    ('pipe', 2, time '07:00', time '23:00'), ('pipe', 3, time '07:00', time '22:00'),
    ('pipe', 4, time '07:00', time '23:00'), ('pipe', 5, time '07:00', time '22:00'),
    ('pipe', 6, time '10:00', time '19:00'),
    -- Berkeley Ironworks
    ('ironworks', 0, time '10:00', time '19:00'), ('ironworks', 1, time '06:00', time '22:00'),
    ('ironworks', 2, time '06:00', time '22:00'), ('ironworks', 3, time '06:00', time '22:00'),
    ('ironworks', 4, time '06:00', time '22:00'), ('ironworks', 5, time '06:00', time '22:00'),
    ('ironworks', 6, time '10:00', time '19:00'),
    -- The Oaks Climbing
    ('the-oaks', 0, time '10:00', time '17:00'), ('the-oaks', 1, time '08:00', time '22:00'),
    ('the-oaks', 2, time '08:00', time '22:00'), ('the-oaks', 3, time '08:00', time '22:00'),
    ('the-oaks', 4, time '08:00', time '22:00'), ('the-oaks', 5, time '08:00', time '22:00'),
    ('the-oaks', 6, time '10:00', time '17:00'),
    -- Mosaic Boulders
    ('mosaic', 0, time '11:00', time '23:00'), ('mosaic', 1, time '13:00', time '23:00'),
    ('mosaic', 2, time '13:00', time '23:00'), ('mosaic', 3, time '13:00', time '23:00'),
    ('mosaic', 4, time '13:00', time '23:00'), ('mosaic', 5, time '13:00', time '23:00'),
    ('mosaic', 6, time '11:00', time '23:00')
) as h(slug, day_of_week, opens_at, closes_at)
join public.gyms g on g.slug = h.slug
on conflict (gym_id, day_of_week) do nothing;

commit;
