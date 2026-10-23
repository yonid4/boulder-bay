import pytest

from app.scrape import __main__ as cli


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
