"""Ranking API contract stubs."""

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from app.api.dependencies import CurrentUser
from app.api.models import DataEnvelope, Rankings

router = APIRouter(
    prefix="/rankings",
    tags=["rankings"],
    responses={
        status.HTTP_501_NOT_IMPLEMENTED: {
            "description": "The endpoint contract exists but its implementation is pending"
        }
    },
)


@router.get("", response_model=DataEnvelope[Rankings])
async def get_rankings(
    current_user: CurrentUser,
    at: Annotated[datetime | None, Query(description="Instant to rank gyms for")] = None,
    limit: Annotated[int, Query(ge=1, le=16, description="Gyms returned per location")] = 16,
) -> DataEnvelope[Rankings]:
    """Get an independent ranked gym list for every saved location."""

    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "Rankings are not implemented")
