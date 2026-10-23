from typing import Any
from uuid import UUID

import pytest

from app.api.models import UserProfile
from app.db import models as db
from app.services.me import ProfileNotFoundError, get_profile

USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")


class FakeSession:
    """Answers `get()` with a canned profile row (or None)."""

    def __init__(self, row: db.Profile | None) -> None:
        self.row = row
        self.calls: list[tuple[Any, Any]] = []

    async def get(self, entity: Any, ident: Any) -> db.Profile | None:
        self.calls.append((entity, ident))
        return self.row


async def test_get_profile_maps_the_row_to_the_contract_model() -> None:
    session = FakeSession(db.Profile(id=USER_ID, display_name="Yoni Dayagi"))

    profile = await get_profile(session, USER_ID)  # type: ignore[arg-type]

    assert profile == UserProfile(id=USER_ID, display_name="Yoni Dayagi")
    assert session.calls == [(db.Profile, USER_ID)]


async def test_get_profile_raises_when_the_row_is_missing() -> None:
    with pytest.raises(ProfileNotFoundError):
        await get_profile(FakeSession(None), USER_ID)  # type: ignore[arg-type]
