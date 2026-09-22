from datetime import UTC, date, datetime, time
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api.models import (
    BusynessForecast,
    BusynessLevel,
    BusynessSource,
    CreateSavedLocation,
    DataEnvelope,
    ForecastPoint,
    Gym,
    GymBrand,
    GymHours,
    GymRates,
    LocationRankings,
    RankedGym,
    Rankings,
    ResolvedBusyness,
    SavedLocation,
)

EXPECTED_OPERATIONS = {
    "/api/gyms": {"get"},
    "/api/gyms/{slug}": {"get"},
    "/api/gyms/{slug}/logo": {"get"},
    "/api/me": {"get"},
    "/api/me/memberships": {"get"},
    "/api/me/memberships/{gym_slug}": {"post", "delete"},
    "/api/me/locations": {"get", "post"},
    "/api/me/locations/{location_id}": {"get", "patch", "delete"},
    "/api/rankings": {"get"},
}


def test_openapi_registers_the_api_contract(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()

    for path, methods in EXPECTED_OPERATIONS.items():
        assert path in schema["paths"]
        assert methods <= set(schema["paths"][path])
        for method in methods:
            operation = schema["paths"][path][method]
            assert operation["security"] == [{"HTTPBearer": []}]
            if (path, method) == ("/api/gyms", "get"):
                assert "200" in operation["responses"]
                assert "501" not in operation["responses"]
            else:
                assert "501" in operation["responses"]

    assert "/api/login" not in schema["paths"]
    assert "/api/logout" not in schema["paths"]
    assert "/api/busyness/{gym_id}" not in schema["paths"]
    assert "/api/busyness_curve/{gym_id}" not in schema["paths"]
    assert "/api/travel_times/{user_id}" not in schema["paths"]


def test_openapi_describes_queries_and_png_logo(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()

    gym_parameters = schema["paths"]["/api/gyms"]["get"]["parameters"]
    assert [parameter["name"] for parameter in gym_parameters] == ["at"]

    ranking_parameters = schema["paths"]["/api/rankings"]["get"]["parameters"]
    assert [parameter["name"] for parameter in ranking_parameters] == ["at", "limit"]
    limit_schema = ranking_parameters[1]["schema"]
    assert limit_schema["default"] == 16
    assert limit_schema["minimum"] == 1
    assert limit_schema["maximum"] == 16

    logo_response = schema["paths"]["/api/gyms/{slug}/logo"]["get"]["responses"]["200"]
    assert "image/png" in logo_response["content"]


def test_api_routes_require_bearer_auth(client: TestClient) -> None:
    unauthenticated = client.get("/api/gyms")
    assert unauthenticated.status_code == 401


def test_grouped_rankings_serialize_with_explicit_wire_names() -> None:
    at = datetime(2026, 9, 13, 18, tzinfo=UTC)
    busyness = ResolvedBusyness(
        at=at,
        is_open=True,
        busy_pct=70,
        level=BusynessLevel.PACKED,
        source=BusynessSource.FORECAST,
    )
    gym = Gym(
        slug="dogpatch",
        name="Dogpatch Boulders",
        brand=GymBrand.TOUCHSTONE,
        city="San Francisco",
        latitude=37.7567,
        longitude=-122.3903,
        logo_url="http://localhost:8000/api/gyms/dogpatch/logo",
        busyness=busyness,
    )
    location = SavedLocation(
        id=UUID("d16878be-c4bc-462f-8929-c464b6a5efad"),
        label="Home",
        address="Redwood City, CA",
        latitude=37.4852,
        longitude=-122.2364,
        is_default=True,
    )
    response = DataEnvelope(
        data=Rankings(
            at=at,
            locations=[
                LocationRankings(
                    location=location,
                    ranked_gyms=[
                        RankedGym(
                            rank=1,
                            score=72.4,
                            travel_minutes=14.2,
                            is_member=True,
                            gym=gym,
                        )
                    ],
                )
            ],
        )
    )

    payload = response.model_dump(mode="json")
    ranked_gym = payload["data"]["locations"][0]["ranked_gyms"][0]
    assert ranked_gym["gym"]["slug"] == "dogpatch"
    assert ranked_gym["gym"]["brand"] == "touchstone"
    assert ranked_gym["gym"]["busyness"] == {
        "at": "2026-09-13T18:00:00Z",
        "is_open": True,
        "busy_pct": 70,
        "level": "packed",
        "source": "forecast",
    }


def test_forecast_supports_an_explicit_open_hour_data_gap() -> None:
    starts_at = datetime(2026, 9, 13, 22, tzinfo=UTC)
    point = ForecastPoint(
        starts_at=starts_at,
        ends_at=datetime(2026, 9, 13, 23, tzinfo=UTC),
    )
    forecast = BusynessForecast(
        date=date(2026, 9, 13),
        timezone="America/Los_Angeles",
        points=[point],
    )

    assert forecast.points[0].busy_pct is None
    assert forecast.points[0].level is None
    assert forecast.best_time is None


def test_location_request_rejects_unknown_fields_and_invalid_coordinates() -> None:
    with pytest.raises(ValidationError):
        CreateSavedLocation(
            label="Home",
            latitude=91,
            longitude=-122.2364,
            make_default=True,
        )

    with pytest.raises(ValidationError):
        CreateSavedLocation.model_validate(
            {
                "label": "Home",
                "latitude": 37.4852,
                "longitude": -122.2364,
                "is_default": True,
            }
        )


def test_schema_uses_local_clock_times_for_hours_and_rates() -> None:
    hours = GymHours(day_of_week=0, opens_at=time(6), closes_at=time(18))
    rates = GymRates(
        day_pass_cents=3_000,
        day_pass_peak_cents=3_500,
        peak_starts_at=time(15),
        monthly_cents=13_000,
    )

    assert hours.model_dump(mode="json") == {
        "day_of_week": 0,
        "opens_at": "06:00:00",
        "closes_at": "18:00:00",
    }
    assert rates.model_dump(mode="json") == {
        "day_pass_cents": 3_000,
        "day_pass_peak_cents": 3_500,
        "peak_starts_at": "15:00:00",
        "monthly_cents": 13_000,
    }
