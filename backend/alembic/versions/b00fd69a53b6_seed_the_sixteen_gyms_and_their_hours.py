"""seed the sixteen gyms and their hours

Part 2 of boulder_bay_schema.sql, transcribed verbatim. Reference data, not user
data: sixteen curated gyms and their 112 opening-hours rows (16 x 7 days).

Both statements are `on conflict ... do nothing`, so re-running is a no-op rather
than an error. `gym_hours` resolves gym ids by joining on `slug` instead of
hardcoding them -- `gyms.id` is `generated always as identity`, so its values are
not knowable when this migration is written.

Revision ID: b00fd69a53b6
Revises: 7bea7599f868
Create Date: 2026-09-08 18:11:38.185236

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b00fd69a53b6'
down_revision: Union[str, Sequence[str], None] = '7bea7599f868'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None



GYMS_SQL = """
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
"""

GYM_HOURS_SQL = """
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
"""

# Every slug this migration owns; downgrade() removes exactly these. Deleting a gym
# cascades to gym_hours, busyness_snapshots, busyness_curves and travel_times.
SEEDED_SLUGS = (
    "mission", "dogpatch", "hyperion", "gwpc", "pipe", "ironworks", "the-oaks",
    "studio", "mv-sf", "mv-belmont", "mv-mountain-view", "mv-santa-clara",
    "bm-sf", "bm-berkeley", "the-peak", "mosaic",
)


def upgrade() -> None:
    """Insert the sixteen gyms, then their hours."""
    op.execute(GYMS_SQL)
    op.execute(GYM_HOURS_SQL)


def downgrade() -> None:
    """Remove only the seeded gyms.

    Scoped to SEEDED_SLUGS rather than truncating, so a gym added later by hand
    survives a downgrade. The gym_hours rows go with them by cascade.
    """
    slugs = ", ".join(f"'{slug}'" for slug in SEEDED_SLUGS)
    op.execute(f"delete from public.gyms where slug in ({slugs})")
