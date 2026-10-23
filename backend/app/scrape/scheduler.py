"""The in-process poll schedule: one job, every :00 and :30 UTC.

`app.main.lifespan` starts it when `SCHEDULER_ENABLED` is true. Run uvicorn with a single
worker and without `--reload`: each worker or reload would start its own scheduler, and
`max_instances` only guards within one process.
"""

import logging
from datetime import UTC, datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import Settings
from app.scrape.notify import broadcast_poll_finished
from app.scrape.poll import load_and_poll
from app.scrape.providers import GoogleMapsProvider, ProviderUnavailable

logger = logging.getLogger(__name__)

TICK_MINUTES = 30
# A run may start this many seconds late (a busy loop, a brief stall) and still count.
MISFIRE_GRACE_SECONDS = 300


def truncate_to_tick(now: datetime) -> datetime:
    """`now` floored to :00 or :30, so a late or repeated run keys to the same tick."""

    return now.replace(minute=now.minute - now.minute % TICK_MINUTES, second=0, microsecond=0)


async def poll_tick(
    session_factory: async_sessionmaker[AsyncSession],
    settings: Settings,
    *,
    now: datetime | None = None,
) -> None:
    """Poll every gym open at this tick. Never raises: the next tick must still run."""

    tick = truncate_to_tick(now or datetime.now(UTC))
    try:
        async with session_factory() as session:
            summary = await load_and_poll(
                session,
                lambda: GoogleMapsProvider(
                    settings.scrape_profile_dir, max_attempts=settings.scrape_max_attempts
                ),
                now=tick,
                open_only=True,
            )
    except ProviderUnavailable as error:
        logger.error("poll %s: Google sign-in unavailable, run --login: %s", tick, error)
        return
    except LookupError as error:
        logger.error("poll %s: gym lookup failed: %s", tick, error)
        return
    except Exception:
        logger.exception("poll %s failed", tick)
        return

    if not summary.results:
        logger.debug("poll %s: no gym is open, nothing to scrape", tick)
        return
    if summary.no_data:
        logger.error(
            "poll %s: no gym returned a single Popular times bar (DOM change?): "
            "check the selectors in app/scrape/providers.py",
            tick,
        )
    failed = [result.slug for result in summary.results if result.error]
    logger.info(
        "poll %s: %d gyms polled, %d failed%s",
        tick,
        len(summary.results),
        len(failed),
        f" ({', '.join(failed)})" if failed else "",
    )

    # Only a tick that wrote new readings is worth a refetch on every connected app.
    if summary.updated:
        await broadcast_poll_finished(
            settings, tick=tick, updated=summary.updated, failed=len(failed)
        )


def create_scheduler(
    session_factory: async_sessionmaker[AsyncSession], settings: Settings
) -> AsyncIOScheduler:
    """An unstarted scheduler holding the single half-hourly `poll_tick` job."""

    scheduler = AsyncIOScheduler(timezone="UTC")
    scheduler.add_job(
        poll_tick,
        CronTrigger(minute="0,30", timezone="UTC"),
        args=[session_factory, settings],
        max_instances=1,
        coalesce=True,
        misfire_grace_time=MISFIRE_GRACE_SECONDS,
    )
    return scheduler
