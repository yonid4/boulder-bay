"""Tell connected apps a poll finished, over Supabase Realtime Broadcast.

The message is only a ping: busyness depends on the requested hour and rankings on each
user's place, so apps refetch from FastAPI rather than read data out of the broadcast. It
carries nothing private, so it goes on a public channel with the anon key.

Each tick opens a socket, joins, sends and closes. A socket held open between ticks would
idle for 30 minutes and need its own reconnect handling.
"""

import asyncio
import logging
from datetime import datetime

from realtime import RealtimeSubscribeStates
from supabase import acreate_client

from app.config import Settings

logger = logging.getLogger(__name__)

POLL_CHANNEL = "polls"
POLL_EVENT = "poll_finished"
# Covers connecting, joining and sending. A ping that misses this is dropped, not retried:
# the next tick sends another, and the app's own refetch still catches up.
BROADCAST_TIMEOUT_SECONDS = 10.0


async def broadcast_poll_finished(
    settings: Settings, *, tick: datetime, updated: int, failed: int
) -> bool:
    """Send one `poll_finished` ping. Never raises; returns whether it was sent.

    `updated` counts gyms that returned a reading this tick; `failed` those that errored.
    """

    if not settings.supabase_anon_key:
        logger.debug("poll %s: SUPABASE_ANON_KEY unset, no Realtime ping", tick)
        return False
    payload = {"tick_at": tick.isoformat(), "updated": updated, "failed": failed}
    try:
        await asyncio.wait_for(_send(settings, payload), BROADCAST_TIMEOUT_SECONDS)
    except Exception as error:
        logger.warning("poll %s: Realtime ping not sent: %r", tick, error)
        return False
    return True


async def _send(settings: Settings, payload: dict[str, object]) -> None:
    client = await acreate_client(settings.supabase_url, settings.supabase_anon_key)
    joined: asyncio.Future[None] = asyncio.get_running_loop().create_future()

    def on_state(state: RealtimeSubscribeStates, error: Exception | None) -> None:
        if joined.done():
            return
        if state == RealtimeSubscribeStates.SUBSCRIBED:
            joined.set_result(None)
        else:
            joined.set_exception(error or RuntimeError(f"channel {state.value}"))

    try:
        channel = client.channel(POLL_CHANNEL)
        # `subscribe` returns before the server acknowledges the join, and a message sent
        # before then is only buffered, so closing straight after would drop it.
        await channel.subscribe(on_state)
        await joined
        await channel.send_broadcast(POLL_EVENT, payload)
    finally:
        await client.realtime.close()
