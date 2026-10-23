"""The authenticated user's profile, gym memberships and saved locations."""

from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.dependencies import CurrentUser, DbSession
from app.api.models import (
    CreateSavedLocation,
    DataEnvelope,
    SavedLocation,
    UpdateSavedLocation,
    UserProfile,
)
from app.services import locations as location_service
from app.services import me as me_service
from app.services import memberships as membership_service

router = APIRouter(prefix="/me", tags=["me"])

LOCATION_NOT_FOUND = "Location not found"
LOCATION_NOT_FOUND_RESPONSE: dict[int | str, dict[str, Any]] = {
    status.HTTP_404_NOT_FOUND: {"description": "No such location for this user"}
}
LOCATION_CONFLICT_RESPONSE: dict[int | str, dict[str, Any]] = {
    status.HTTP_409_CONFLICT: {
        "description": "Duplicate label, a second home or a second work location"
    }
}


@router.get(
    "",
    response_model=DataEnvelope[UserProfile],
    responses={status.HTTP_404_NOT_FOUND: {"description": "The user has no profile row"}},
)
async def get_me(current_user: CurrentUser, session: DbSession) -> DataEnvelope[UserProfile]:
    """Get the authenticated user's application profile."""

    try:
        profile = await me_service.get_profile(session, current_user.id)
    except me_service.ProfileNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not found") from error
    return DataEnvelope(data=profile)


@router.get("/memberships", response_model=DataEnvelope[list[str]])
async def list_memberships(
    current_user: CurrentUser, session: DbSession
) -> DataEnvelope[list[str]]:
    """Get the slugs of gyms the authenticated user belongs to, ordered by gym name."""

    slugs = await membership_service.list_membership_slugs(session, user_id=current_user.id)
    return DataEnvelope(data=slugs)


@router.post(
    "/memberships/{gym_slug}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={status.HTTP_404_NOT_FOUND: {"description": "Unknown or inactive gym"}},
)
async def add_membership(gym_slug: str, current_user: CurrentUser, session: DbSession) -> None:
    """Idempotently add one gym to the authenticated user's memberships."""

    try:
        await membership_service.add_membership(session, user_id=current_user.id, slug=gym_slug)
    except membership_service.GymNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Gym not found") from error


@router.delete(
    "/memberships/{gym_slug}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={status.HTTP_404_NOT_FOUND: {"description": "Unknown or inactive gym"}},
)
async def remove_membership(gym_slug: str, current_user: CurrentUser, session: DbSession) -> None:
    """Idempotently remove one gym from the authenticated user's memberships."""

    try:
        await membership_service.remove_membership(session, user_id=current_user.id, slug=gym_slug)
    except membership_service.GymNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Gym not found") from error


@router.get("/locations", response_model=DataEnvelope[list[SavedLocation]])
async def list_locations(
    current_user: CurrentUser, session: DbSession
) -> DataEnvelope[list[SavedLocation]]:
    """Get saved locations in creation order."""

    locations = await location_service.list_locations(session, user_id=current_user.id)
    return DataEnvelope(data=locations)


@router.post(
    "/locations",
    response_model=DataEnvelope[SavedLocation],
    status_code=status.HTTP_201_CREATED,
    responses=LOCATION_CONFLICT_RESPONSE,
)
async def create_location(
    location: CreateSavedLocation, current_user: CurrentUser, session: DbSession
) -> DataEnvelope[SavedLocation]:
    """Create a location. The user's first location becomes the default."""

    try:
        created = await location_service.create_location(
            session, user_id=current_user.id, location=location
        )
    except location_service.LocationConflictError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, error.detail) from error
    return DataEnvelope(data=created)


@router.get(
    "/locations/{location_id}",
    response_model=DataEnvelope[SavedLocation],
    responses=LOCATION_NOT_FOUND_RESPONSE,
)
async def get_location(
    location_id: UUID, current_user: CurrentUser, session: DbSession
) -> DataEnvelope[SavedLocation]:
    """Get one location owned by the authenticated user."""

    try:
        location = await location_service.get_location(
            session, user_id=current_user.id, location_id=location_id
        )
    except location_service.LocationNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, LOCATION_NOT_FOUND) from error
    return DataEnvelope(data=location)


@router.patch(
    "/locations/{location_id}",
    response_model=DataEnvelope[SavedLocation],
    responses={**LOCATION_NOT_FOUND_RESPONSE, **LOCATION_CONFLICT_RESPONSE},
)
async def update_location(
    location_id: UUID,
    location: UpdateSavedLocation,
    current_user: CurrentUser,
    session: DbSession,
) -> DataEnvelope[SavedLocation]:
    """Update one location or promote it to be the default."""

    try:
        updated = await location_service.update_location(
            session, user_id=current_user.id, location_id=location_id, changes=location
        )
    except location_service.LocationNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, LOCATION_NOT_FOUND) from error
    except location_service.LocationConflictError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, error.detail) from error
    return DataEnvelope(data=updated)


@router.delete(
    "/locations/{location_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        **LOCATION_NOT_FOUND_RESPONSE,
        status.HTTP_409_CONFLICT: {"description": "It is the user's only location"},
    },
)
async def delete_location(location_id: UUID, current_user: CurrentUser, session: DbSession) -> None:
    """Delete a location; deleting the default promotes the oldest remaining one."""

    try:
        await location_service.delete_location(
            session, user_id=current_user.id, location_id=location_id
        )
    except location_service.LocationNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, LOCATION_NOT_FOUND) from error
    except location_service.LastLocationError as error:
        raise HTTPException(
            status.HTTP_409_CONFLICT, location_service.LAST_LOCATION_MESSAGE
        ) from error
