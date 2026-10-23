import logging
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def restore_app_logger() -> Iterator[None]:
    """Undo `configure_logging`, which every lifespan run applies to the `app` logger.

    A level it leaves set would filter DEBUG records out of later tests' `caplog`.
    """

    app_logger = logging.getLogger("app")
    level, handlers = app_logger.level, list(app_logger.handlers)
    yield
    app_logger.setLevel(level)
    app_logger.handlers[:] = handlers
