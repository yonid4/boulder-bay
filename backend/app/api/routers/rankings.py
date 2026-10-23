"""Rankings: the best gyms right now (or at `at`) from one saved location."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from app.api.dependencies import CurrentUser, DbSession
from app.api.models import DataEnvelope, Rankings
from app.config import Settings, get_settings
from app.services import locations as location_service
from app.services import ranking as ranking_service
from app.services.travel import MapboxClient, get_mapbox_client

LOCATION_NOT_FOUND = "Location not found"
LOCATION_REQUIRED = "A saved location is required"

router = APIRouter(prefix="/rankings", tags=["rankings"])


@router.get(
    "",
    response_model=DataEnvelope[Rankings],
    responses={
        status.HTTP_404_NOT_FOUND: {"description": "No such location for this user"},
        status.HTTP_409_CONFLICT: {
            "description": "No `location_id` was given and the user has no saved locations"
        },
    },
)
async def get_rankings(
    request: Request,
    current_user: CurrentUser,
    session: DbSession,
    settings: Annotated[Settings, Depends(get_settings)],
    mapbox: Annotated[MapboxClient, Depends(get_mapbox_client)],
    location_id: Annotated[
        UUID | None, Query(description="Saved location to rank from; default: the default one")
    ] = None,
    at: Annotated[datetime | None, Query(description="Instant to rank gyms for")] = None,
    limit: Annotated[int, Query(ge=1, le=16, description="Most gyms returned")] = 16,
) -> DataEnvelope[Rankings]:
    """Rank the active gyms within reach of one saved location, best first."""

    try:
        rankings = await ranking_service.rank_gyms(
            session,
            user_id=current_user.id,
            location_id=location_id,
            mapbox=mapbox,
            radius_meters=settings.ranking_radius_meters,
            limit=limit,
            at=at,
            logo_url_for=lambda slug: str(request.url_for("get_gym_logo", slug=slug)),
        )
    except ValueError as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error)) from error
    except location_service.LocationNotFoundError as error:
        raise HTTPException(status.HTTP_404_NOT_FOUND, LOCATION_NOT_FOUND) from error
    except location_service.NoLocationsError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, LOCATION_REQUIRED) from error
    return DataEnvelope(data=rankings)
