from collections.abc import Iterator
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.api.routers import me as me_router
from app.main import app
from app.services.memberships import GymNotFoundError

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
SESSION = object()

Call = tuple[str, Any, UUID, str | None]


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
def calls(monkeypatch: pytest.MonkeyPatch) -> list[Call]:
    recorded: list[Call] = []

    async def fake_list(session: object, *, user_id: UUID) -> list[str]:
        recorded.append(("list", session, user_id, None))
        return ["dogpatch", "mission-cliffs"]

    async def fake_add(session: object, *, user_id: UUID, slug: str) -> None:
        recorded.append(("add", session, user_id, slug))
        if slug == "nope":
            raise GymNotFoundError(slug)

    async def fake_remove(session: object, *, user_id: UUID, slug: str) -> None:
        recorded.append(("remove", session, user_id, slug))
        if slug == "nope":
            raise GymNotFoundError(slug)

    monkeypatch.setattr(me_router.membership_service, "list_membership_slugs", fake_list)
    monkeypatch.setattr(me_router.membership_service, "add_membership", fake_add)
    monkeypatch.setattr(me_router.membership_service, "remove_membership", fake_remove)
    return recorded


def test_list_returns_enveloped_slugs_for_the_token_user(
    authed_client: TestClient, calls: list[Call]
) -> None:
    response = authed_client.get("/api/me/memberships")

    assert response.status_code == 200
    assert response.json() == {"data": ["dogpatch", "mission-cliffs"]}
    assert calls == [("list", SESSION, USER_ID, None)]


def test_post_returns_204_with_empty_body(authed_client: TestClient, calls: list[Call]) -> None:
    response = authed_client.post("/api/me/memberships/dogpatch")

    assert response.status_code == 204
    assert response.content == b""
    assert calls == [("add", SESSION, USER_ID, "dogpatch")]


def test_post_repeated_still_returns_204(authed_client: TestClient, calls: list[Call]) -> None:
    first = authed_client.post("/api/me/memberships/dogpatch")
    second = authed_client.post("/api/me/memberships/dogpatch")

    assert first.status_code == second.status_code == 204


def test_delete_returns_204_even_when_repeated(
    authed_client: TestClient, calls: list[Call]
) -> None:
    first = authed_client.delete("/api/me/memberships/dogpatch")
    second = authed_client.delete("/api/me/memberships/dogpatch")

    assert first.status_code == second.status_code == 204
    assert first.content == b""
    assert calls[0] == ("remove", SESSION, USER_ID, "dogpatch")


@pytest.mark.parametrize("method", ["post", "delete"])
def test_unknown_slug_is_404(authed_client: TestClient, calls: list[Call], method: str) -> None:
    response = getattr(authed_client, method)("/api/me/memberships/nope")

    assert response.status_code == 404
    assert response.json() == {"detail": "Gym not found"}


def test_memberships_require_authentication() -> None:
    assert TestClient(app).get("/api/me/memberships").status_code in {401, 403}
