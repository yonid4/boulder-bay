from collections.abc import Iterator
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.api.models import UserProfile
from app.api.routers import me as me_router
from app.main import app
from app.services.me import ProfileNotFoundError

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
SESSION = object()


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


def test_get_me_returns_the_enveloped_profile(
    authed_client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: list[tuple[object, UUID]] = []

    async def fake_get_profile(session: object, user_id: UUID) -> UserProfile:
        calls.append((session, user_id))
        return UserProfile(id=user_id, display_name="Yoni Dayagi")

    monkeypatch.setattr(me_router.me_service, "get_profile", fake_get_profile)

    response = authed_client.get("/api/me")

    assert response.status_code == 200
    assert response.json() == {"data": {"id": str(USER_ID), "display_name": "Yoni Dayagi"}}
    assert calls == [(SESSION, USER_ID)]


def test_get_me_is_404_when_the_profile_row_is_missing(
    authed_client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def missing(session: object, user_id: UUID) -> Any:
        raise ProfileNotFoundError(user_id)

    monkeypatch.setattr(me_router.me_service, "get_profile", missing)

    response = authed_client.get("/api/me")

    assert response.status_code == 404
    assert response.json() == {"detail": "Profile not found"}
