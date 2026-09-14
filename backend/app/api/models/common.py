"""Models shared by every API domain."""

from typing import Generic, TypeVar

from pydantic import BaseModel

DataT = TypeVar("DataT")


class DataEnvelope(BaseModel, Generic[DataT]):
    """Successful JSON responses use a consistent top-level data key."""

    data: DataT
