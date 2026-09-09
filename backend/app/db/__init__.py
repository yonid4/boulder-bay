# Importing `models` for its side effect: it registers every table on
# `Base.metadata`, which `alembic/env.py` uses as the autogenerate target. Without
# this import Alembic sees an empty metadata and proposes dropping all nine tables.
from app.db import models
from app.db.base import Base

__all__ = ["Base", "models"]
