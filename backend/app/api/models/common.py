"""Models shared by every API domain."""

from datetime import datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel

DataT = TypeVar("DataT")


class DataEnvelope(BaseModel, Generic[DataT]):
    """Successful JSON responses use a consistent top-level data key."""

    data: DataT


class HealthStatus(BaseModel):
    """`/health`: the process is up, and when the poller last wrote a snapshot.

    `last_successful_poll_at` is `max(busyness_snapshots.observed_at)` -- the tick of the
    newest snapshot, so a lapsed Google sign-in or a sleeping host shows as a stale value.
    `poll_state` says whether that value could be read: with `"known"`, null means no
    snapshot exists yet; with `"unknown"`, the database query failed and the time is null.
    """

    status: Literal["ok"] = "ok"
    last_successful_poll_at: datetime | None
    poll_state: Literal["known", "unknown"]
