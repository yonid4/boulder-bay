"""Gym summary and detail models."""

from datetime import time
from enum import StrEnum

from pydantic import AnyHttpUrl, BaseModel, Field

from app.api.models.busyness import BusynessForecast, ResolvedBusyness


class GymBrand(StrEnum):
    MOVEMENT = "movement"
    TOUCHSTONE = "touchstone"
    BENCHMARK = "benchmark"
    INDEPENDENT = "independent"


class Gym(BaseModel):
    slug: str
    name: str
    brand: GymBrand
    city: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    logo_url: AnyHttpUrl | None = None
    busyness: ResolvedBusyness


class GymHours(BaseModel):
    """One weekday's local opening hours; Sunday is day zero."""

    day_of_week: int = Field(ge=0, le=6)
    opens_at: time
    closes_at: time


class GymRates(BaseModel):
    """Display rates in integer cents; peak fields are both absent for flat rates."""

    day_pass_cents: int | None = Field(default=None, ge=0)
    day_pass_peak_cents: int | None = Field(default=None, ge=0)
    peak_starts_at: time | None = None
    monthly_cents: int | None = Field(default=None, ge=0)


class GymDetail(BaseModel):
    gym: Gym
    address: str | None = None
    timezone: str
    website_url: AnyHttpUrl | None = None
    waiver_url: AnyHttpUrl | None = None
    hours: list[GymHours]
    rates: GymRates
    forecast: BusynessForecast
