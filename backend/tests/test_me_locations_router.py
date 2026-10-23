from collections.abc import Iterator
from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import AuthenticatedUser, get_session, require_user
from app.api.models import (
    CreateSavedLocation,
    LocationKind,
    SavedLocation,
    UpdateSavedLocation,
)
from app.api.routers import me as me_router
from app.main import app
from app.services.locations import (
    CONFLICT_MESSAGES,
    LastLocationError,
    LocationConflictError,
    LocationNotFoundError,
)

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")
HOME_ID = UUID("d16878be-c4bc-462f-8929-c464b6a5efad")
MISSING_ID = UUID("00000000-0000-4000-8000-000000000000")
SESSION = object()

HOME = SavedLocation(
    id=HOME_ID,
    label="Home",
    address="Redwood City, CA",
    latitude=37.4852,
    longitude=-122.2364,
    is_default=True,
    kind=LocationKind.HOME,
)
HOME_JSON = {
    "id": str(HOME_ID),
    "label": "Home",
    "address": "Redwood City, CA",
    "latitude": 37.4852,
    "longitude": -122.2364,
    "is_default": True,
    "kind": "home",
}


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
def calls(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, dict[str, Any]]]:
    """Fake service: `MISSING_ID` is not found; a label names the error to raise."""

    recorded: list[tuple[str, dict[str, Any]]] = []
    service = me_router.location_service

    def check(location_id: UUID) -> None:
        if location_id == MISSING_ID:
            raise LocationNotFoundError(location_id)

    def maybe_conflict(label: str | None) -> None:
        if label in CONFLICT_MESSAGES:
            raise LocationConflictError(label)

    async def fake_list(session: object, *, user_id: UUID) -> list[SavedLocation]:
        recorded.append(("list", {"session": session, "user_id": user_id}))
        return [HOME]

    async def fake_get(session: object, *, user_id: UUID, location_id: UUID) -> SavedLocation:
        recorded.append(("get", {"session": session, "user_id": user_id, "id": location_id}))
        check(location_id)
        return HOME

    async def fake_create(
        session: object, *, user_id: UUID, location: CreateSavedLocation
    ) -> SavedLocation:
        recorded.append(("create", {"session": session, "user_id": user_id, "body": location}))
        maybe_conflict(location.label)
        return HOME

    async def fake_update(
        session: object, *, user_id: UUID, location_id: UUID, changes: UpdateSavedLocation
    ) -> SavedLocation:
        recorded.append(
            ("update", {"session": session, "user_id": user_id, "id": location_id, "body": changes})
        )
        check(location_id)
        maybe_conflict(changes.label)
        return HOME

    async def fake_delete(session: object, *, user_id: UUID, location_id: UUID) -> None:
        recorded.append(("delete", {"session": session, "user_id": user_id, "id": location_id}))
        check(location_id)
        if location_id == HOME_ID:
            raise LastLocationError(location_id)

    monkeypatch.setattr(service, "list_locations", fake_list)
    monkeypatch.setattr(service, "get_location", fake_get)
    monkeypatch.setattr(service, "create_location", fake_create)
    monkeypatch.setattr(service, "update_location", fake_update)
    monkeypatch.setattr(service, "delete_location", fake_delete)
    return recorded


CREATE_BODY = {
    "label": "Home",
    "kind": "home",
    "address": "Redwood City, CA",
    "latitude": 37.4852,
    "longitude": -122.2364,
}


def test_list_returns_enveloped_locations_for_the_token_user(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.get("/api/me/locations")

    assert response.status_code == 200
    assert response.json() == {"data": [HOME_JSON]}
    assert calls == [("list", {"session": SESSION, "user_id": USER_ID})]


def test_get_returns_one_location(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.get(f"/api/me/locations/{HOME_ID}")

    assert response.status_code == 200
    assert response.json() == {"data": HOME_JSON}
    assert calls[0][1]["id"] == HOME_ID
    assert calls[0][1]["user_id"] == USER_ID


def test_create_returns_201_with_the_location(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.post("/api/me/locations", json=CREATE_BODY)

    assert response.status_code == 201
    assert response.json() == {"data": HOME_JSON}
    body = calls[0][1]["body"]
    assert body.kind is LocationKind.HOME
    assert body.make_default is False
    assert calls[0][1]["user_id"] == USER_ID


def test_create_requires_kind(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    body = {key: value for key, value in CREATE_BODY.items() if key != "kind"}

    response = authed_client.post("/api/me/locations", json=body)

    assert response.status_code == 422
    assert calls == []


def test_create_rejects_an_unknown_kind(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.post("/api/me/locations", json={**CREATE_BODY, "kind": "gym"})

    assert response.status_code == 422
    assert calls == []


def test_patch_passes_only_the_supplied_fields(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.patch(
        f"/api/me/locations/{HOME_ID}", json={"kind": "work", "make_default": True}
    )

    assert response.status_code == 200
    assert response.json() == {"data": HOME_JSON}
    changes = calls[0][1]["body"]
    assert changes.model_fields_set == {"kind", "make_default"}
    assert calls[0][1]["id"] == HOME_ID


def test_delete_returns_204_with_empty_body(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    other_id = UUID("5b0f9f4e-7a39-4d0e-9a53-2f7c1f8a6b21")

    response = authed_client.delete(f"/api/me/locations/{other_id}")

    assert response.status_code == 204
    assert response.content == b""
    assert calls == [("delete", {"session": SESSION, "user_id": USER_ID, "id": other_id})]


def test_deleting_the_last_location_is_409(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]]
) -> None:
    response = authed_client.delete(f"/api/me/locations/{HOME_ID}")

    assert response.status_code == 409
    assert response.json() == {"detail": "You can't delete your only place"}


@pytest.mark.parametrize(
    ("method", "body"),
    [("get", None), ("patch", {"label": "Casa"}), ("delete", None)],
)
def test_unknown_or_foreign_location_is_404(
    authed_client: TestClient,
    calls: list[tuple[str, dict[str, Any]]],
    method: str,
    body: dict[str, Any] | None,
) -> None:
    kwargs = {"json": body} if body is not None else {}

    response = authed_client.request(method, f"/api/me/locations/{MISSING_ID}", **kwargs)

    assert response.status_code == 404
    assert response.json() == {"detail": "Location not found"}


@pytest.mark.parametrize("constraint", sorted(CONFLICT_MESSAGES))
def test_create_conflict_is_409_with_its_message(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]], constraint: str
) -> None:
    response = authed_client.post("/api/me/locations", json={**CREATE_BODY, "label": constraint})

    assert response.status_code == 409
    assert response.json() == {"detail": CONFLICT_MESSAGES[constraint]}


@pytest.mark.parametrize("constraint", sorted(CONFLICT_MESSAGES))
def test_update_conflict_is_409_with_its_message(
    authed_client: TestClient, calls: list[tuple[str, dict[str, Any]]], constraint: str
) -> None:
    response = authed_client.patch(f"/api/me/locations/{HOME_ID}", json={"label": constraint})

    assert response.status_code == 409
    assert response.json() == {"detail": CONFLICT_MESSAGES[constraint]}


def test_locations_require_authentication() -> None:
    assert TestClient(app).get("/api/me/locations").status_code in {401, 403}
