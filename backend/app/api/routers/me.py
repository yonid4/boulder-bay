"""Authenticated profile, membership, and saved-location contract stubs."""

from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.dependencies import CurrentUser
from app.api.models import (
    CreateSavedLocation,
    DataEnvelope,
    SavedLocation,
    UpdateSavedLocation,
    UserProfile,
)

router = APIRouter(
    prefix="/me",
    tags=["me"],
    responses={
        status.HTTP_501_NOT_IMPLEMENTED: {
            "description": "The endpoint contract exists but its implementation is pending"
        }
    },
)


@router.get("", response_model=DataEnvelope[UserProfile])
async def get_me(current_user: CurrentUser) -> DataEnvelope[UserProfile]:
    """Get the authenticated user's application profile."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Profiles are not implemented")


@router.get("/memberships", response_model=DataEnvelope[list[str]])
async def list_memberships(current_user: CurrentUser) -> DataEnvelope[list[str]]:
    """Get the slugs of gyms the authenticated user belongs to."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Memberships are not implemented")


@router.post("/memberships/{gym_slug}", status_code=status.HTTP_204_NO_CONTENT)
async def add_membership(gym_slug: str, current_user: CurrentUser) -> None:
    """Idempotently add one gym to the authenticated user's memberships."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Memberships are not implemented")


@router.delete("/memberships/{gym_slug}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_membership(gym_slug: str, current_user: CurrentUser) -> None:
    """Idempotently remove one gym from the authenticated user's memberships."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Memberships are not implemented")


@router.get("/locations", response_model=DataEnvelope[list[SavedLocation]])
async def list_locations(current_user: CurrentUser) -> DataEnvelope[list[SavedLocation]]:
    """Get saved locations in creation order."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Saved locations are not implemented")


@router.post(
    "/locations",
    response_model=DataEnvelope[SavedLocation],
    status_code=status.HTTP_201_CREATED,
)
async def create_location(
    location: CreateSavedLocation, current_user: CurrentUser
) -> DataEnvelope[SavedLocation]:
    """Create one of the authenticated user's three allowed locations."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Saved locations are not implemented")


@router.get("/locations/{location_id}", response_model=DataEnvelope[SavedLocation])
async def get_location(location_id: UUID, current_user: CurrentUser) -> DataEnvelope[SavedLocation]:
    """Get one location owned by the authenticated user."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Saved locations are not implemented")


@router.patch("/locations/{location_id}", response_model=DataEnvelope[SavedLocation])
async def update_location(
    location_id: UUID,
    location: UpdateSavedLocation,
    current_user: CurrentUser,
) -> DataEnvelope[SavedLocation]:
    """Update one location or promote it to be the default."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Saved locations are not implemented")


@router.delete("/locations/{location_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_location(location_id: UUID, current_user: CurrentUser) -> None:
    """Delete a location while preserving the one-default invariant."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Saved locations are not implemented")
