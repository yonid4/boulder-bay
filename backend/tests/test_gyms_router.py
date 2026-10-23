from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.api.models import Gym, GymBrand, ResolvedBusyness
from app.api.routers import gyms as gyms_router
from app.main import app
from app.services.gyms import GymLogoImage

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
        is_member=True,
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

    async def fake_list_gyms(
        session: object,
        *,
        user_id: UUID,
        at: datetime | None = None,
        logo_url_for: Callable[[str], str] | None = None,
    ) -> list[Gym]:
        calls.append(
            {"session": session, "user_id": user_id, "at": at, "logo_url_for": logo_url_for}
        )
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
                "is_member": True,
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
    assert service_calls[0]["session"] is SESSION
    assert service_calls[0]["at"] is None
    assert service_calls[0]["user_id"] == USER_ID


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


def test_list_gyms_gives_the_service_an_absolute_logo_url_builder(
    authed_client: TestClient, service_calls: list[dict[str, Any]]
) -> None:
    authed_client.get("/api/gyms")

    build = service_calls[0]["logo_url_for"]
    assert build("dogpatch") == "http://testserver/api/gyms/dogpatch/logo"


LOGO = GymLogoImage(image=b"\x89PNG-bytes", content_type="image/png", sha256="ab12cd")
ETAG = '"ab12cd"'


@pytest.fixture
def logo_lookup(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    slugs: list[str] = []

    async def fake_get_gym_logo(session: object, slug: str) -> GymLogoImage | None:
        slugs.append(slug)
        return LOGO if slug == "dogpatch" else None

    monkeypatch.setattr(gyms_router.gym_service, "get_gym_logo", fake_get_gym_logo)
    return slugs


def test_logo_returns_the_bytes_with_etag_and_cache_control(
    authed_client: TestClient, logo_lookup: list[str]
) -> None:
    response = authed_client.get("/api/gyms/dogpatch/logo")

    assert response.status_code == 200
    assert response.content == LOGO.image
    assert response.headers["content-type"] == "image/png"
    assert response.headers["etag"] == ETAG
    assert response.headers["cache-control"] == "private, max-age=86400"
    assert logo_lookup == ["dogpatch"]


@pytest.mark.parametrize(
    "if_none_match",
    [ETAG, f"W/{ETAG}", f'"other", {ETAG}', "*"],
)
def test_logo_returns_304_without_a_body_when_if_none_match_matches(
    authed_client: TestClient, logo_lookup: list[str], if_none_match: str
) -> None:
    response = authed_client.get(
        "/api/gyms/dogpatch/logo", headers={"If-None-Match": if_none_match}
    )

    assert response.status_code == 304
    assert response.content == b""
    assert response.headers["etag"] == ETAG
    assert response.headers["cache-control"] == "private, max-age=86400"


def test_logo_returns_the_bytes_when_if_none_match_is_stale(
    authed_client: TestClient, logo_lookup: list[str]
) -> None:
    response = authed_client.get("/api/gyms/dogpatch/logo", headers={"If-None-Match": '"old"'})

    assert response.status_code == 200
    assert response.content == LOGO.image


def test_logo_is_404_for_an_unknown_slug_or_a_gym_without_a_logo(
    authed_client: TestClient, logo_lookup: list[str]
) -> None:
    response = authed_client.get("/api/gyms/nope/logo", headers={"If-None-Match": "*"})

    assert response.status_code == 404


def test_logo_still_requires_auth(client: TestClient) -> None:
    assert client.get("/api/gyms/dogpatch/logo").status_code == 401
