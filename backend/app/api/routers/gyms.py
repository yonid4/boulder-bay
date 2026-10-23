"""Gym routes. Listing and logo are live; detail is still a contract stub."""

from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException, Query, Request, Response, status

from app.api.dependencies import CurrentUser, DbSession
from app.api.models import DataEnvelope, Gym, GymDetail
from app.services import gyms as gym_service

LOGO_CACHE_CONTROL = "private, max-age=86400"

router = APIRouter(prefix="/gyms", tags=["gyms"])

NOT_IMPLEMENTED_RESPONSES: dict[int | str, dict[str, Any]] = {
    status.HTTP_501_NOT_IMPLEMENTED: {
        "description": "The endpoint contract exists but its implementation is pending"
    }
}


@router.get("", response_model=DataEnvelope[list[Gym]])
async def list_gyms(
    request: Request,
    current_user: CurrentUser,
    session: DbSession,
    at: Annotated[datetime | None, Query(description="Instant to resolve busyness for")] = None,
) -> DataEnvelope[list[Gym]]:
    """Get all curated gyms with busyness resolved for `at` or now."""

    try:
        gyms = await gym_service.list_gyms(
            session,
            user_id=current_user.id,
            at=at,
            logo_url_for=lambda slug: str(request.url_for("get_gym_logo", slug=slug)),
        )
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


def etag_matches(if_none_match: str, etag: str) -> bool:
    """Weak comparison of an `If-None-Match` header against `etag` (RFC 9110 section 13.1.2)."""

    for candidate in if_none_match.split(","):
        candidate = candidate.strip().removeprefix("W/")
        if candidate in ("*", etag):
            return True
    return False


@router.get(
    "/{slug}/logo",
    response_class=Response,
    responses={
        status.HTTP_200_OK: {
            "content": {"image/png": {}},
            "description": "The gym's PNG logo",
        },
        status.HTTP_304_NOT_MODIFIED: {"description": "`If-None-Match` matches the logo's ETag"},
        status.HTTP_404_NOT_FOUND: {"description": "Unknown gym, or a gym with no logo"},
    },
)
async def get_gym_logo(
    slug: str,
    current_user: CurrentUser,
    session: DbSession,
    if_none_match: Annotated[str | None, Header()] = None,
) -> Response:
    """Get the logo assigned to a gym, revalidatable by ETag."""

    logo = await gym_service.get_gym_logo(session, slug)
    if logo is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Gym logo not found")

    headers = {"ETag": f'"{logo.sha256}"', "Cache-Control": LOGO_CACHE_CONTROL}
    if if_none_match is not None and etag_matches(if_none_match, headers["ETag"]):
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)
    return Response(content=logo.image, media_type=logo.content_type, headers=headers)
