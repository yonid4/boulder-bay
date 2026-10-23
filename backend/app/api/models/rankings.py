"""Gym ranking models: one saved location's ranked gyms."""

from datetime import datetime

from pydantic import BaseModel, Field

from app.api.models.gyms import Gym
from app.api.models.locations import SavedLocation


class RankedGym(BaseModel):
    """One gym's place in the ranking; membership is `gym.is_member`.

    `score` is unrounded (higher is better), and the app rounds it for display.
    """

    rank: int = Field(ge=1)
    score: float
    travel_minutes: float = Field(ge=0)
    gym: Gym


class Rankings(BaseModel):
    at: datetime
    location: SavedLocation
    ranked_gyms: list[RankedGym]
