"""Gym API contract stubs."""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status

from app.api.dependencies import CurrentUser
from app.api.models import DataEnvelope, Gym, GymDetail

router = APIRouter(
    prefix="/gyms",
    tags=["gyms"],
    responses={
        status.HTTP_501_NOT_IMPLEMENTED: {
            "description": "The endpoint contract exists but its implementation is pending"
        }
    },
)


@router.get("", response_model=DataEnvelope[list[Gym]])
async def list_gyms(
    current_user: CurrentUser,
    at: Annotated[datetime | None, Query(description="Instant to resolve busyness for")] = None,
) -> DataEnvelope[list[Gym]]:
    """Get all curated gyms with busyness resolved for `at` or now."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Gym listing is not implemented")


@router.get("/{slug}", response_model=DataEnvelope[GymDetail])
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
        }
    },
)
async def get_gym_logo(slug: str, current_user: CurrentUser) -> Response:
    """Get the logo assigned to a gym."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Gym logos are not implemented")
