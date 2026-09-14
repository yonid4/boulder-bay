"""Saved-location request and response models."""

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class SavedLocation(BaseModel):
    id: UUID
    label: str
    address: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    is_default: bool


class CreateSavedLocation(BaseModel):
    """Coordinates come from the app's MapKit place search."""

    model_config = ConfigDict(extra="forbid")

    label: str
    address: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    make_default: bool = False


class UpdateSavedLocation(BaseModel):
    """Only supplied fields are changed; true promotes this location to default."""

    model_config = ConfigDict(extra="forbid")

    label: str | None = None
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    make_default: bool | None = None
