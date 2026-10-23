"""The one-shot Popular times scrape.

uv run python -m app.scrape --login         sign the scrape profile in to Google, once
uv run python -m app.scrape --dry-run       scrape and print every day's bars, write nothing
uv run python -m app.scrape [--gym SLUG]    scrape and write curves and snapshots

--open-only skips the gyms that are closed right now; without it a closed gym is scraped.
A run that writes new readings sends the scheduler's Realtime `poll_finished` ping too.
"""

import argparse
import asyncio
import logging
import sys
from collections.abc import Sequence
from datetime import UTC, datetime

from app.config import get_settings
from app.db.session import create_session_factory
from app.scrape.notify import broadcast_poll_finished
from app.scrape.parse import WEEKDAYS, CrowdReading
from app.scrape.poll import PollSummary, load_and_poll
from app.scrape.providers import GoogleMapsProvider, ProviderUnavailable, open_login_window


def format_bars(reading: CrowdReading) -> list[str]:
    """One line per weekday, 6 AM-11 PM, so a dry run can be checked against Maps."""

    lines = []
    for day, name in enumerate(WEEKDAYS):
        cells = [
            f"{reading.bars[(day, hour)]:>4}" if (day, hour) in reading.bars else "   ."
            for hour in range(6, 24)
        ]
        lines.append(f"    {name[:3]} {''.join(cells)}")
    return lines


def format_summary(summary: PollSummary, *, dry_run: bool) -> str:
    lines = []
    for result in summary.results:
        reading = result.reading
        place = reading.place_name if reading and reading.place_name else "?"
        live = f"{reading.live_pct}/{reading.typical_pct}" if reading else "-"
        status = result.error or "ok"
        lines.append(
            f"{result.slug:<14} {place:<34} bars={result.bars:<3} rows={result.curve_rows:<3} "
            f"live/usual={live:<7} attempts={result.attempts} {status}"
        )
        if dry_run and reading:
            hours = "".join(f"{hour % 12 or 12:>4}" for hour in range(6, 24))
            lines.append(f"        {hours}")
            lines.extend(format_bars(reading))
    return "\n".join(lines)


async def scrape(slugs: Sequence[str], *, dry_run: bool, open_only: bool = False) -> int:
    settings = get_settings()
    now = datetime.now(UTC)
    engine, session_factory = create_session_factory(settings.database_url)
    try:
        async with session_factory() as session:
            summary = await load_and_poll(
                session,
                lambda: GoogleMapsProvider(
                    settings.scrape_profile_dir, max_attempts=settings.scrape_max_attempts
                ),
                now=now,
                slugs=slugs,
                open_only=open_only,
                dry_run=dry_run,
            )
    except LookupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except ProviderUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        await engine.dispose()

    if not summary.results:
        print("no gyms to scrape: none is open right now")
        return 0
    print(format_summary(summary, dry_run=dry_run))
    # Same ping as a scheduler tick, stamped with the real time rather than :00 or :30. A dry
    # run wrote nothing, so there is nothing for apps to refetch.
    if not dry_run and summary.updated:
        failed = sum(1 for result in summary.results if result.error)
        await broadcast_poll_finished(settings, tick=now, updated=summary.updated, failed=failed)
    if summary.no_data:
        print(
            "error: no gym returned a single Popular times bar. That is a DOM change, not a "
            "flaky load: check the selectors in app/scrape/providers.py.",
            file=sys.stderr,
        )
        return 1
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.scrape",
        description="Scrape Google Maps Popular times into busyness_curves and snapshots.",
    )
    parser.add_argument(
        "--login",
        action="store_true",
        help="open a browser to sign the scraper's profile in to Google, then exit",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print each gym's bars per day; write nothing"
    )
    parser.add_argument(
        "--gym",
        action="append",
        default=[],
        metavar="SLUG",
        help="only scrape this gym (repeatable)",
    )
    parser.add_argument(
        "--open-only", action="store_true", help="skip gyms that are closed right now"
    )
    args = parser.parse_args(argv)

    if args.login:
        profile_dir = get_settings().scrape_profile_dir
        print("Sign in to Google in the window that opens, then quit it (Cmd+Q).")
        print(f"Profile: {profile_dir}")
        return open_login_window(profile_dir)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    return asyncio.run(scrape(args.gym, dry_run=args.dry_run, open_only=args.open_only))


if __name__ == "__main__":
    raise SystemExit(main())
