"""Gym routes. Listing is live; detail and logo are still contract stubs."""

from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.api.dependencies import CurrentUser, DbSession
from app.api.models import DataEnvelope, Gym, GymDetail
from app.services import gyms as gym_service

router = APIRouter(prefix="/gyms", tags=["gyms"])

NOT_IMPLEMENTED_RESPONSES: dict[int | str, dict[str, Any]] = {
    status.HTTP_501_NOT_IMPLEMENTED: {
        "description": "The endpoint contract exists but its implementation is pending"
    }
}


@router.get("", response_model=DataEnvelope[list[Gym]])
async def list_gyms(
    current_user: CurrentUser,
    session: DbSession,
    at: Annotated[datetime | None, Query(description="Instant to resolve busyness for")] = None,
) -> DataEnvelope[list[Gym]]:
    """Get all curated gyms with busyness resolved for `at` or now."""

    try:
        gyms = await gym_service.list_gyms(session, at=at)
    except ValueError as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error)) from error
    return DataEnvelope(data=gyms)


@router.get("/{slug}", response_model=DataEnvelope[GymDetail], responses=NOT_IMPLEMENTED_RESPONSES)
async def get_gym(
    slug: str,
    current_user: CurrentUser,
    at: Annotated[datetime | None, Query(description="Instant to resolve busyness for")] = None,
) -> DataEnvelope[GymDetail]:
    """Get consolidated gym details and the local day's forecast."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Gym detail is not implemented")


@router.get(
    "/{slug}/logo",
    response_class=Response,
    responses={
        status.HTTP_200_OK: {
            "content": {"image/png": {}},
            "description": "The gym's PNG logo",
        },
        **NOT_IMPLEMENTED_RESPONSES,
    },
)
async def get_gym_logo(slug: str, current_user: CurrentUser) -> Response:
    """Get the logo assigned to a gym."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Gym logos are not implemented")
