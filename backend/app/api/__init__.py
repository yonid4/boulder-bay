"""HTTP API composition for Boulder Bay."""

from fastapi import APIRouter

from app.api.routers import gyms, me, rankings

api_router = APIRouter(prefix="/api")
api_router.include_router(gyms.router)
api_router.include_router(me.router)
api_router.include_router(rankings.router)

__all__ = ["api_router"]
