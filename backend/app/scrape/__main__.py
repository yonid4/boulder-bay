"""The one-shot Popular times scrape.

uv run python -m app.scrape --login         sign the scrape profile in to Google, once
uv run python -m app.scrape --dry-run       scrape and print every day's bars, write nothing
uv run python -m app.scrape [--gym SLUG]    scrape and write curves and snapshots
"""

import argparse
import asyncio
import logging
import sys
from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import models as db
from app.db.session import create_session_factory
from app.scrape.parse import WEEKDAYS, CrowdReading
from app.scrape.poll import PollSummary, run_poll
from app.scrape.providers import GoogleMapsProvider, ProviderUnavailable, open_login_window


async def load_gyms(
    session: AsyncSession, slugs: Sequence[str]
) -> tuple[list[db.Gym], dict[int, list[db.GymHours]]]:
    """Active gyms by name, optionally limited to `slugs`, and their opening hours."""

    gyms_stmt = select(db.Gym).where(db.Gym.is_active).order_by(db.Gym.name)
    if slugs:
        gyms_stmt = gyms_stmt.where(db.Gym.slug.in_(slugs))
    gyms = list((await session.scalars(gyms_stmt)).all())
    if missing := sorted(set(slugs) - {gym.slug for gym in gyms}):
        raise LookupError(f"unknown or inactive gym slug(s): {', '.join(missing)}")

    hours: dict[int, list[db.GymHours]] = {gym.id: [] for gym in gyms}
    hours_stmt = select(db.GymHours).where(db.GymHours.gym_id.in_(hours))
    for row in (await session.scalars(hours_stmt)).all():
        hours[row.gym_id].append(row)
    return gyms, hours


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


async def scrape(slugs: Sequence[str], *, dry_run: bool) -> int:
    settings = get_settings()
    engine, session_factory = create_session_factory(settings.database_url)
    try:
        async with session_factory() as session:
            gyms, hours = await load_gyms(session, slugs)
            # End the read transaction; it would otherwise idle through the whole scrape.
            await session.commit()
            provider = GoogleMapsProvider(
                settings.scrape_profile_dir, max_attempts=settings.scrape_max_attempts
            )
            async with provider:
                summary = await run_poll(
                    session, provider, gyms, hours, now=datetime.now(UTC), dry_run=dry_run
                )
    except LookupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except ProviderUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        await engine.dispose()

    print(format_summary(summary, dry_run=dry_run))
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
    args = parser.parse_args(argv)

    if args.login:
        profile_dir = get_settings().scrape_profile_dir
        print("Sign in to Google in the window that opens, then quit it (Cmd+Q).")
        print(f"Profile: {profile_dir}")
        return open_login_window(profile_dir)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    return asyncio.run(scrape(args.gym, dry_run=args.dry_run))


if __name__ == "__main__":
    raise SystemExit(main())
