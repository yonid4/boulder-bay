"""Locks the ORM models against the agreed design in `boulder_bay_schema.md`.

The models are the DDL source of truth, so nothing else checks them. These tests are
what stop the design document and the code drifting apart silently: a constraint
renamed in one and not the other is otherwise invisible until a migration produces
the wrong DDL.
"""

from sqlalchemy import Computed

from app.db import Base
from app.db.models import Gym, GymLogo, SavedLocation

EXPECTED_TABLES = {
    "busyness_curves",
    "busyness_snapshots",
    "gym_hours",
    "gym_logos",
    "gym_memberships",
    "gyms",
    "profiles",
    "ranking_prefs",
    "saved_locations",
    "travel_times",
}

# Every CHECK constraint in the agreed design (boulder_bay_schema.md §2), by name.
EXPECTED_CHECK_CONSTRAINTS = {
    "busyness_curves_day_range",
    "busyness_curves_hour_range",
    "busyness_curves_pct_range",
    "busyness_snapshots_live_range",
    "busyness_snapshots_typical_range",
    "gym_hours_day_range",
    "gym_hours_ordered",
    "gym_logos_byte_size_positive",
    "gym_logos_content_type_valid",
    "gym_logos_key_format",
    "gyms_brand_valid",
    "gyms_day_pass_nonneg",
    "gyms_latitude_range",
    "gyms_longitude_range",
    "gyms_monthly_nonneg",
    "gyms_peak_pass_nonneg",
    "gyms_peak_rate_complete",
    "gyms_slug_format",
    "ranking_prefs_travel_cap_positive",
    "saved_locations_latitude_range",
    "saved_locations_longitude_range",
    "travel_times_meters_nonneg",
    "travel_times_minutes_nonneg",
    "travel_times_provider_valid",
}


def test_all_ten_tables_are_registered() -> None:
    assert set(Base.metadata.tables) == EXPECTED_TABLES


def test_check_constraint_names_match_the_ddl() -> None:
    found = {
        constraint.name
        for table in Base.metadata.tables.values()
        for constraint in table.constraints
        if type(constraint).__name__ == "CheckConstraint"
    }
    assert found == EXPECTED_CHECK_CONSTRAINTS


def test_geog_columns_are_stored_generated_columns() -> None:
    """`geog` is derived from latitude/longitude by Postgres, never written by the
    API. If this stops being a stored generated column the scraper and the ranking
    endpoint silently diverge from the coordinates."""
    for model in (Gym, SavedLocation):
        geog = model.__table__.c.geog
        assert isinstance(geog.computed, Computed), f"{model.__name__}.geog not generated"
        assert geog.computed.persisted is True, f"{model.__name__}.geog not STORED"
        # Schema-qualified: the migration connection pins search_path to `public`
        # and PostGIS lives in `extensions`.
        assert "extensions.st_makepoint" in str(geog.computed.sqltext)


def test_geog_columns_do_not_carry_an_implicit_spatial_index() -> None:
    """geoalchemy2 creates a spatial index as a side effect of the type unless told
    not to. That index is invisible in the model but real in the database, and
    autogenerate then proposes dropping and re-adding it on every run. `gyms` gets
    its index declared explicitly instead; `saved_locations` gets none at all."""
    for model in (Gym, SavedLocation):
        assert model.__table__.c.geog.type.spatial_index is False

    assert {index.name for index in Gym.__table__.indexes} == {"gyms_geog_idx"}
    assert {index.name for index in SavedLocation.__table__.indexes} == {
        "saved_locations_user_idx",
        "saved_locations_one_default_idx",
    }


def test_gyms_reference_their_logo_by_foreign_key() -> None:
    """Sixteen gyms share twelve marks, and `gyms.logo_id` is the whole mechanism that
    expresses the sharing. It replaced an `Image("logo-\\(slug)")`-else-brand lookup in the
    app bundle; if this FK goes away that string convention is the only thing left."""
    logo_id = Gym.__table__.c.logo_id
    fk = next(iter(logo_id.foreign_keys))
    assert fk.column is GymLogo.__table__.c.id
    # Dropping a mark must not take gyms with it.
    assert fk.ondelete == "SET NULL"
    # Nullable on purpose: adding a gym is not blocked on sourcing a logo.
    assert logo_id.nullable is True
