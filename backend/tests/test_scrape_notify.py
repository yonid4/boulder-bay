import logging
from datetime import UTC, datetime
from typing import Any

import pytest
from realtime import RealtimeSubscribeStates

from app.config import Settings
from app.scrape import notify

TICK = datetime(2026, 10, 23, 18, 30, tzinfo=UTC)


def make_settings(anon_key: str = "anon") -> Settings:
    # Passed explicitly so a real `.env` key never leaks into the test.
    return Settings(
        database_url="postgresql+asyncpg://u:pw@db.example.com:5432/postgres",
        supabase_url="https://example.supabase.co",
        supabase_anon_key=anon_key,
    )


class FakeChannel:
    def __init__(self, join: RealtimeSubscribeStates | None) -> None:
        # The state the server "answers" the join with; None never answers.
        self.join = join
        self.sent: list[tuple[str, Any]] = []

    async def subscribe(self, callback: Any) -> "FakeChannel":
        if self.join is not None:
            callback(self.join, None)
        return self

    async def send_broadcast(self, event: str, data: Any) -> None:
        self.sent.append((event, data))


class FakeRealtime:
    def __init__(self) -> None:
        self.closed = 0

    async def close(self) -> None:
        self.closed += 1


class FakeClient:
    def __init__(self, join: RealtimeSubscribeStates | None) -> None:
        self.realtime = FakeRealtime()
        self.channels: dict[str, FakeChannel] = {}
        self.join = join

    def channel(self, topic: str) -> FakeChannel:
        self.channels[topic] = FakeChannel(self.join)
        return self.channels[topic]


def install_client(
    monkeypatch: pytest.MonkeyPatch,
    join: RealtimeSubscribeStates | None = RealtimeSubscribeStates.SUBSCRIBED,
    error: Exception | None = None,
) -> list[tuple[tuple[str, str], FakeClient]]:
    created: list[tuple[tuple[str, str], FakeClient]] = []

    async def fake_create(url: str, key: str) -> FakeClient:
        if error is not None:
            raise error
        client = FakeClient(join)
        created.append(((url, key), client))
        return client

    monkeypatch.setattr(notify, "acreate_client", fake_create)
    return created


async def test_sends_one_ping_on_the_polls_channel_and_closes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    created = install_client(monkeypatch)

    sent = await notify.broadcast_poll_finished(make_settings(), tick=TICK, updated=7, failed=1)

    assert sent is True
    ((args, client),) = created
    assert args == ("https://example.supabase.co", "anon")
    assert client.channels["polls"].sent == [
        ("poll_finished", {"tick_at": "2026-10-23T18:30:00+00:00", "updated": 7, "failed": 1})
    ]
    assert client.realtime.closed == 1


async def test_skips_without_an_anon_key(monkeypatch: pytest.MonkeyPatch) -> None:
    created = install_client(monkeypatch)

    sent = await notify.broadcast_poll_finished(
        make_settings(anon_key=""), tick=TICK, updated=7, failed=0
    )

    assert sent is False
    assert created == []


@pytest.mark.parametrize(
    "join", [RealtimeSubscribeStates.CHANNEL_ERROR, RealtimeSubscribeStates.TIMED_OUT]
)
async def test_a_refused_join_sends_nothing_and_warns(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    join: RealtimeSubscribeStates,
) -> None:
    created = install_client(monkeypatch, join=join)

    sent = await notify.broadcast_poll_finished(make_settings(), tick=TICK, updated=7, failed=0)

    assert sent is False
    ((_, client),) = created
    assert client.channels["polls"].sent == []
    assert client.realtime.closed == 1
    assert any(r.levelno == logging.WARNING for r in caplog.records)


async def test_a_join_that_never_answers_times_out(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    monkeypatch.setattr(notify, "BROADCAST_TIMEOUT_SECONDS", 0.01)
    created = install_client(monkeypatch, join=None)

    sent = await notify.broadcast_poll_finished(make_settings(), tick=TICK, updated=7, failed=0)

    assert sent is False
    ((_, client),) = created
    assert client.channels["polls"].sent == []
    assert client.realtime.closed == 1
    assert any(r.levelno == logging.WARNING for r in caplog.records)


async def test_a_connect_error_never_raises(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    install_client(monkeypatch, error=OSError("refused"))

    sent = await notify.broadcast_poll_finished(make_settings(), tick=TICK, updated=7, failed=0)

    assert sent is False
    assert any(r.levelno == logging.WARNING for r in caplog.records)


async def test_a_sent_ping_is_logged_at_info(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    install_client(monkeypatch)

    with caplog.at_level(logging.INFO):
        await notify.broadcast_poll_finished(make_settings(), tick=TICK, updated=7, failed=1)

    (record,) = caplog.records
    assert record.levelno == logging.INFO
    assert record.getMessage() == (
        "poll 2026-10-23 18:30:00+00:00: Realtime ping sent (7 updated, 1 failed)"
    )
