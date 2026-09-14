"""Per-location gym ranking models."""

from datetime import datetime

from pydantic import BaseModel, Field

from app.api.models.gyms import Gym
from app.api.models.locations import SavedLocation


class RankedGym(BaseModel):
    rank: int = Field(ge=1)
    score: float
    travel_minutes: float = Field(ge=0)
    is_member: bool
    gym: Gym


class LocationRankings(BaseModel):
    location: SavedLocation
    ranked_gyms: list[RankedGym]


class Rankings(BaseModel):
    at: datetime
    locations: list[LocationRankings]
