"""Resolved and forecast busyness models."""

from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class BusynessLevel(StrEnum):
    """Quiet below 40%, moderate from 40-69%, and packed from 70%."""

    QUIET = "quiet"
    MODERATE = "moderate"
    PACKED = "packed"


class BusynessSource(StrEnum):
    LIVE = "live"
    FORECAST = "forecast"


class ResolvedBusyness(BaseModel):
    """Busyness resolved for one requested instant.

    A missing percentage means either that the gym is closed (`is_open` is false)
    or that it is open but no live/forecast value is available (`is_open` is true).
    """

    at: datetime
    is_open: bool
    busy_pct: int | None = Field(default=None, ge=0, le=100)
    level: BusynessLevel | None = None
    source: BusynessSource | None = None


class ForecastPoint(BaseModel):
    starts_at: datetime
    ends_at: datetime
    busy_pct: int | None = Field(default=None, ge=0, le=100)
    level: BusynessLevel | None = None


class BusynessForecast(BaseModel):
    """Typical-week forecast for one local calendar day."""

    date: date
    timezone: str
    points: list[ForecastPoint]
    best_time: ForecastPoint | None = None
