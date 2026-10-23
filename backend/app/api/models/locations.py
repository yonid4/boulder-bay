"""Saved-location request and response models."""

from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class LocationKind(StrEnum):
    """At most one `home` and one `work` per user; `other` is unlimited and means nothing."""

    HOME = "home"
    WORK = "work"
    OTHER = "other"


class SavedLocation(BaseModel):
    id: UUID
    label: str
    address: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    is_default: bool
    kind: LocationKind


class CreateSavedLocation(BaseModel):
    """Coordinates come from the app's MapKit place search."""

    model_config = ConfigDict(extra="forbid")

    label: str
    kind: LocationKind
    address: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    make_default: bool = False


class UpdateSavedLocation(BaseModel):
    """Only supplied fields are changed; true promotes this location to default."""

    model_config = ConfigDict(extra="forbid")

    label: str | None = None
    kind: LocationKind | None = None
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    make_default: bool | None = None
