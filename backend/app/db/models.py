"""SQLAlchemy models for the ten application tables.

These models are the DDL source of truth. The design they implement — and the
alternatives it rejected — is `../boulder_bay_schema.md`; keep the two in step,
which `tests/test_models.py` enforces for the parts it can.

Three things here deliberately do NOT round-trip through autogenerate and are
hand-written in the initial migration instead:

1. `profiles.id -> auth.users(id)`. Autogenerate is restricted to `public`
   (`alembic/env.py`), so it cannot see the `auth` schema and would emit no FK.
   Declaring it here would also force a stub `auth.users` Table into the metadata.
2. The `geog` generated-column expressions. PostGIS lives in the `extensions`
   schema and the migration connection pins `search_path` to `public`, so the
   expression must name `extensions.*` explicitly.
3. The RLS enable/revoke block (see `../boulder_bay_schema.md` §4).

`alembic/env.py` excludes the `geog` columns and `gyms_geog_idx` from autogenerate
so they are not re-proposed on every run.
"""

from datetime import datetime, time
from decimal import Decimal
from uuid import UUID

from geoalchemy2 import Geography
from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Computed,
    DateTime,
    Double,
    ForeignKey,
    Identity,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    SmallInteger,
    Text,
    Time,
    UniqueConstraint,
    Uuid,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

# The generated-column body, shared by `gyms` and `saved_locations`. Schema-qualified
# because the migration connection runs with `search_path = public` and PostGIS is
# installed into `extensions` (supabase/migrations/20260907072340_enable_postgis.sql).
_GEOG_EXPR = (
    "extensions.geography("
    "extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326))"
)


# Point geography, WGS84. `spatial_index=False` on every one of these: geoalchemy2
# otherwise creates an index as a side effect of the type, which autogenerate then
# proposes dropping and re-adding forever. Indexes are declared explicitly below.
def _geog_column() -> Mapped[str | None]:
    return mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        Computed(_GEOG_EXPR, persisted=True),
        nullable=True,
    )


class Profile(Base):
    """Mirrors `auth.users` so the rest of the schema has an FK target in `public`.

    Rows are created by the Supabase-owned `auth.users` signup trigger. The FK to
    `auth.users(id)` is added by hand in the migration -- see the module docstring.
    """

    __tablename__ = "profiles"
    __table_args__ = (
        CheckConstraint(
            "display_name = regexp_replace(display_name, '^[[:space:]]+|[[:space:]]+$', '', 'g')",
            name="profiles_display_name_trimmed",
        ),
        CheckConstraint(
            "char_length(display_name) between 1 and 80",
            name="profiles_display_name_length",
        ),
        CheckConstraint(
            "display_name ~ '^[A-Za-z ]+$'",
            name="profiles_display_name_format",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True)
    display_name: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class GymLogo(Base):
    """The twelve gym marks, stored as bytes so the app fetches them from the API rather
    than carrying an asset catalog.

    Twelve rows for sixteen gyms: ten per-gym marks plus two brand-level ones, `movement`
    covering the four Movement locations and `benchmark` the two Benchmark ones. `gyms.logo_id`
    records which is which, so the old slug-else-brand asset lookup is gone -- sharing is a
    foreign key, not a naming convention, and `key` is only a readable name for the row.

    The bytes are seeded from `alembic/versions/data/logos/<key>.png`; see that directory's
    README. At Bay Area scale this is 574 KB across twelve rows. If the gym list ever stops
    being curated, `bytea` is the part to revisit -- see `../boulder_bay_schema.md` §2.10.
    """

    __tablename__ = "gym_logos"
    __table_args__ = (
        # Same shape as gyms.slug: these keys are slugs or brand values verbatim.
        CheckConstraint(r"key ~ '^[a-z0-9-]+$'", name="gym_logos_key_format"),
        CheckConstraint("byte_size > 0", name="gym_logos_byte_size_positive"),
        # Every seeded mark is a PNG. Widen this before storing anything else.
        CheckConstraint("content_type in ('image/png')", name="gym_logos_content_type_valid"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    key: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    content_type: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'image/png'")
    )
    image: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    # Denormalised so a listing can report sizes without detoasting `image`.
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False)
    # Hex digest of `image`. Unused for now; it is what a future ETag is cut from.
    sha256: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class Gym(Base):
    """The sixteen curated gyms. Surrogate bigint PK; `slug` is the public identifier
    (routes, seed data) but nothing references it."""

    __tablename__ = "gyms"
    __table_args__ = (
        CheckConstraint(r"slug ~ '^[a-z0-9-]+$'", name="gyms_slug_format"),
        CheckConstraint(
            "brand in ('movement', 'touchstone', 'benchmark', 'independent')",
            name="gyms_brand_valid",
        ),
        CheckConstraint("latitude between -90 and 90", name="gyms_latitude_range"),
        CheckConstraint("longitude between -180 and 180", name="gyms_longitude_range"),
        CheckConstraint("day_pass_cents >= 0", name="gyms_day_pass_nonneg"),
        CheckConstraint("day_pass_peak_cents >= 0", name="gyms_peak_pass_nonneg"),
        CheckConstraint("monthly_cents >= 0", name="gyms_monthly_nonneg"),
        # Half a tier is always a bug: a peak price with no start time (or the reverse)
        # cannot be rendered. num_nulls() counts NULLs among its arguments.
        CheckConstraint(
            "num_nulls(day_pass_peak_cents, peak_starts_at) <> 1",
            name="gyms_peak_rate_complete",
        ),
        # Backs the straight-line pre-filter that narrows candidates before Mapbox is
        # called. Query with extensions.st_dwithin(g.geog, :loc, :meters) -- a bare
        # st_distance(...) <= x does NOT use this index, it seq-scans. geography
        # distances are METERS (miles = m / 1609.344).
        Index("gyms_geog_idx", "geog", postgresql_using="gist"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    slug: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    brand: Mapped[str] = mapped_column(Text, nullable=False)
    city: Mapped[str] = mapped_column(Text, nullable=False)
    address: Mapped[str | None] = mapped_column(Text)  # NULL until verified; see seed
    latitude: Mapped[float] = mapped_column(Double, nullable=False)
    longitude: Mapped[float] = mapped_column(Double, nullable=False)
    geog: Mapped[str | None] = _geog_column()
    timezone: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'America/Los_Angeles'")
    )
    # Search string the scraper falls back to.
    google_maps_query: Mapped[str] = mapped_column(Text, nullable=False)
    # Canonical /maps/place/ URL; preferred, skips search disambiguation.
    google_maps_url: Mapped[str | None] = mapped_column(Text)
    website_url: Mapped[str | None] = mapped_column(Text)
    waiver_url: Mapped[str | None] = mapped_column(Text)
    # Which mark to render. Nullable so adding a gym is not blocked on sourcing a logo;
    # all sixteen seeded gyms resolve. SET NULL: dropping a mark must not drop a gym.
    logo_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("gym_logos.id", ondelete="SET NULL")
    )
    # Day-rate tiering: Touchstone charges $30 before 3pm and $35 after. Both peak
    # columns are NULL for a gym with one flat day rate, which is most of them.
    # `peak_starts_at` is local clock time, interpreted in `timezone` like gym_hours.
    day_pass_cents: Mapped[int | None] = mapped_column(Integer)
    day_pass_peak_cents: Mapped[int | None] = mapped_column(Integer)
    peak_starts_at: Mapped[time | None] = mapped_column(Time)
    monthly_cents: Mapped[int | None] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class GymHours(Base):
    """Feeds the detail screen, the closed-gym ranking penalty, and "best time to
    climb" (the future *open* hour with the lowest predicted busyness)."""

    __tablename__ = "gym_hours"
    __table_args__ = (
        CheckConstraint("day_of_week between 0 and 6", name="gym_hours_day_range"),
        # Past-midnight closing is rejected for v1: no seed gym does it, and allowing
        # it forces every "is it open now" query to branch.
        CheckConstraint("closes_at > opens_at", name="gym_hours_ordered"),
    )

    gym_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gyms.id", ondelete="CASCADE"), primary_key=True
    )
    day_of_week: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    opens_at: Mapped[time] = mapped_column(Time, nullable=False)
    closes_at: Mapped[time] = mapped_column(Time, nullable=False)


class BusynessSnapshot(Base):
    """The time series we own. One row per gym per poll (30 min, open hours only).

    Observability and drift measurement -- NOT a prediction input; forecasts come
    from `busyness_curves`.
    """

    __tablename__ = "busyness_snapshots"
    __table_args__ = (
        # Makes a re-run of a poll idempotent. This index also serves the "latest
        # reading per gym" read (scanned backwards), so there is no second index.
        UniqueConstraint("gym_id", "observed_at", name="busyness_snapshots_tick_unique"),
        CheckConstraint("live_pct between 0 and 100", name="busyness_snapshots_live_range"),
        CheckConstraint("typical_pct between 0 and 100", name="busyness_snapshots_typical_range"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    gym_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gyms.id", ondelete="CASCADE"), nullable=False
    )
    # The poll tick, not now().
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # NULL when Google reports no live reading.
    live_pct: Mapped[int | None] = mapped_column(SmallInteger)
    # The "usually N% busy" half of the same label.
    typical_pct: Mapped[int | None] = mapped_column(SmallInteger)
    source: Mapped[str] = mapped_column(Text, nullable=False, server_default=text("'google_maps'"))


class BusynessCurve(Base):
    """Google's typical-week histogram; the single source for the time scrubber and
    "best time to climb". Refreshed by upsert on every poll.

    NOTE: a scrape never contains the current hour's bar (that element carries the
    live label instead), so upsert the bars you got and leave the current hour's
    stored row alone. Never delete-then-insert, or you punch an hourly hole each run.

    CLOSED HOURS HAVE NO ROW. Google renders ~18 bars/day, so hours 0-5 are simply
    absent. Do NOT seed them as busy_pct = 0 -- that is indistinguishable from a
    genuinely empty gym and destroys the only signal there is. A missing row means
    "no data"; join `gym_hours` to decide whether that is "closed" (expected) or a
    scraper gap (a bug you want to see).
    """

    __tablename__ = "busyness_curves"
    __table_args__ = (
        CheckConstraint("day_of_week between 0 and 6", name="busyness_curves_day_range"),
        CheckConstraint("hour_of_day between 0 and 23", name="busyness_curves_hour_range"),
        CheckConstraint("busy_pct between 0 and 100", name="busyness_curves_pct_range"),
    )

    gym_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gyms.id", ondelete="CASCADE"), primary_key=True
    )
    day_of_week: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    hour_of_day: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    busy_pct: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    # Last time Google confirmed this bar.
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class GymMembership(Base):
    """Drives the ranking boost and the dark pin ring on the map.

    Per-gym rows, deliberately, even though most people hold a chain membership.
    Both chains also sell single-gym and home-gym tiers, so per-gym rows are the MORE
    general model -- a brand column could not express them.
    """

    __tablename__ = "gym_memberships"

    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    gym_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gyms.id", ondelete="CASCADE"), primary_key=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class SavedLocation(Base):
    """uuid PK because the id is handed to the client in
    `GET /api/rankings?location_id=` and shouldn't be enumerable."""

    __tablename__ = "saved_locations"
    __table_args__ = (
        UniqueConstraint("user_id", "label", name="saved_locations_label_unique"),
        CheckConstraint("latitude between -90 and 90", name="saved_locations_latitude_range"),
        CheckConstraint("longitude between -180 and 180", name="saved_locations_longitude_range"),
        Index("saved_locations_user_idx", "user_id"),
        # At most one default per user, enforced in the database rather than the API.
        # Promoting a new default must clear the old one first, in the same transaction.
        # There is no deferred-constraint escape hatch -- deferral works on unique
        # CONSTRAINTS, and constraints cannot be partial, so `where is_default` forces
        # an index.
        Index(
            "saved_locations_one_default_idx",
            "user_id",
            unique=True,
            postgresql_where=text("is_default"),
        ),
        # No GiST index: a user has ~3 of these and they are always fetched by user_id.
    )

    id: Mapped[UUID] = mapped_column(
        Uuid, primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    label: Mapped[str] = mapped_column(Text, nullable=False)
    address: Mapped[str | None] = mapped_column(Text)
    latitude: Mapped[float] = mapped_column(Double, nullable=False)
    longitude: Mapped[float] = mapped_column(Double, nullable=False)
    geog: Mapped[str | None] = _geog_column()
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class RankingPrefs(Base):
    """Defaults are exactly the prototype formula, so an untouched account scores
    identically to the mockup. The base 100 stays a constant in Python -- it's a
    presentation offset, not a tunable."""

    __tablename__ = "ranking_prefs"
    __table_args__ = (
        CheckConstraint("travel_cap_minutes > 0", name="ranking_prefs_travel_cap_positive"),
    )

    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True
    )
    w_crowd: Mapped[Decimal] = mapped_column(
        Numeric(5, 3), nullable=False, server_default=text("0.6")
    )
    w_travel: Mapped[Decimal] = mapped_column(
        Numeric(5, 3), nullable=False, server_default=text("0.5")
    )
    member_boost: Mapped[Decimal] = mapped_column(
        Numeric(5, 2), nullable=False, server_default=text("15")
    )
    closed_penalty: Mapped[Decimal] = mapped_column(
        Numeric(5, 2), nullable=False, server_default=text("60")
    )
    travel_cap_minutes: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("60")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class TravelTime(Base):
    """Mapbox Matrix cache: 3 locations x 16 gyms = 48 near-static pairs, refreshed on
    the order of weeks. Keyed by location_id so moving a location invalidates by
    cascade."""

    __tablename__ = "travel_times"
    __table_args__ = (
        # A row from the `6 + miles * 2.3` fallback is visibly second-class and gets
        # re-fetched first.
        CheckConstraint(
            "provider in ('mapbox', 'haversine_fallback')", name="travel_times_provider_valid"
        ),
        CheckConstraint("minutes >= 0", name="travel_times_minutes_nonneg"),
        CheckConstraint("meters >= 0", name="travel_times_meters_nonneg"),
    )

    location_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("saved_locations.id", ondelete="CASCADE"), primary_key=True
    )
    gym_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("gyms.id", ondelete="CASCADE"), primary_key=True
    )
    minutes: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False)
    meters: Mapped[int | None] = mapped_column(Integer)
    provider: Mapped[str] = mapped_column(Text, nullable=False, server_default=text("'mapbox'"))
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
