from types import SimpleNamespace
from typing import Any

import pytest

from app.scrape import __main__ as cli
from app.scrape.parse import CrowdReading
from app.scrape.poll import GymResult, PollSummary


@pytest.mark.parametrize(
    ("argv", "open_only"), [([], False), (["--open-only"], True)], ids=["default", "open-only"]
)
def test_open_only_flag_reaches_the_scrape(
    monkeypatch: pytest.MonkeyPatch, argv: list[str], open_only: bool
) -> None:
    seen: dict[str, object] = {}

    async def fake_scrape(slugs: list[str], *, dry_run: bool, open_only: bool) -> int:
        seen.update(slugs=slugs, dry_run=dry_run, open_only=open_only)
        return 0

    monkeypatch.setattr(cli, "scrape", fake_scrape)

    assert cli.main([*argv, "--gym", "dogpatch", "--dry-run"]) == 0
    assert seen == {"slugs": ["dogpatch"], "dry_run": True, "open_only": open_only}


class FakeEngine:
    async def dispose(self) -> None:
        return None


class FakeSessionFactory:
    def __call__(self) -> "FakeSessionFactory":
        return self

    async def __aenter__(self) -> object:
        return object()

    async def __aexit__(self, *exc: object) -> None:
        return None


def reading() -> CrowdReading:
    return CrowdReading(place_name="Gym", live_pct=40, typical_pct=50, bars={(4, 9): 40})


def install_scrape(
    monkeypatch: pytest.MonkeyPatch, summary: PollSummary
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    polls: list[dict[str, Any]] = []
    pings: list[dict[str, Any]] = []

    async def fake_load_and_poll(session: object, open_provider: object, **kwargs: Any) -> Any:
        polls.append(kwargs)
        return summary

    async def fake_broadcast(settings: object, **kwargs: Any) -> bool:
        pings.append(kwargs)
        return True

    monkeypatch.setattr(cli, "get_settings", lambda: SimpleNamespace(database_url="db"))
    monkeypatch.setattr(
        cli, "create_session_factory", lambda url: (FakeEngine(), FakeSessionFactory())
    )
    monkeypatch.setattr(cli, "load_and_poll", fake_load_and_poll)
    monkeypatch.setattr(cli, "broadcast_poll_finished", fake_broadcast)
    return polls, pings


async def test_a_real_scrape_pings_apps_with_the_run_time(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    polls, pings = install_scrape(
        monkeypatch,
        PollSummary(
            [
                GymResult(slug="a", reading=reading()),
                GymResult(slug="b", error="timeout"),
            ]
        ),
    )

    assert await cli.scrape([], dry_run=False) == 0

    assert pings == [{"tick": polls[0]["now"], "updated": 1, "failed": 1}]


async def test_a_dry_run_never_pings(monkeypatch: pytest.MonkeyPatch) -> None:
    _, pings = install_scrape(monkeypatch, PollSummary([GymResult(slug="a", reading=reading())]))

    assert await cli.scrape([], dry_run=True) == 0

    assert pings == []


@pytest.mark.parametrize(
    "summary",
    [PollSummary([GymResult(slug="a")]), PollSummary([GymResult(slug="a", error="timeout")])],
    ids=["no-bars", "all-failed"],
)
async def test_a_scrape_without_new_readings_never_pings(
    monkeypatch: pytest.MonkeyPatch, summary: PollSummary
) -> None:
    _, pings = install_scrape(monkeypatch, summary)

    await cli.scrape([], dry_run=False)

    assert pings == []
