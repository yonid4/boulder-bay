from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.api.models import Gym, GymBrand, ResolvedBusyness
from app.api.routers import gyms as gyms_router
from app.main import app

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
AT = datetime(2026, 9, 14, 19, tzinfo=UTC)
SESSION = object()


def make_gym() -> Gym:
    return Gym(
        slug="dogpatch",
        name="Dogpatch Boulders",
        brand=GymBrand.TOUCHSTONE,
        city="San Francisco",
        latitude=37.7567,
        longitude=-122.3903,
        busyness=ResolvedBusyness(at=AT, is_open=True),
    )


@pytest.fixture
def authed_client() -> Iterator[TestClient]:
    async def fake_user() -> AuthenticatedUser:
        return AuthenticatedUser(id=USER_ID)

    async def fake_session() -> object:
        return SESSION

    app.dependency_overrides[require_user] = fake_user
    app.dependency_overrides[get_session] = fake_session
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def service_calls(monkeypatch: pytest.MonkeyPatch) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []

    async def fake_list_gyms(session: object, *, at: datetime | None = None) -> list[Gym]:
        calls.append({"session": session, "at": at})
        if at is not None and at.tzinfo is None:
            raise ValueError("`at` must carry a timezone offset")
        return [make_gym()]

    monkeypatch.setattr(gyms_router.gym_service, "list_gyms", fake_list_gyms)
    return calls


def test_list_gyms_returns_enveloped_gyms_from_the_service(
    authed_client: TestClient, service_calls: list[dict[str, Any]]
) -> None:
    response = authed_client.get("/api/gyms")

    assert response.status_code == 200
    assert response.json() == {
        "data": [
            {
                "slug": "dogpatch",
                "name": "Dogpatch Boulders",
                "brand": "touchstone",
                "city": "San Francisco",
                "latitude": 37.7567,
                "longitude": -122.3903,
                "logo_url": None,
                "busyness": {
                    "at": "2026-09-14T19:00:00Z",
                    "is_open": True,
                    "busy_pct": None,
                    "level": None,
                    "source": None,
                },
            }
        ]
    }
    assert service_calls == [{"session": SESSION, "at": None}]


def test_list_gyms_passes_at_through_to_the_service(
    authed_client: TestClient, service_calls: list[dict[str, Any]]
) -> None:
    response = authed_client.get("/api/gyms", params={"at": "2026-09-14T12:00:00-07:00"})

    assert response.status_code == 200
    assert service_calls[0]["at"] == AT


def test_list_gyms_rejects_a_naive_at(
    authed_client: TestClient, service_calls: list[dict[str, Any]]
) -> None:
    response = authed_client.get("/api/gyms", params={"at": "2026-09-14T12:00:00"})

    assert response.status_code == 422
    assert "timezone" in response.json()["detail"]


def test_list_gyms_still_requires_auth(client: TestClient) -> None:
    assert client.get("/api/gyms").status_code == 401
