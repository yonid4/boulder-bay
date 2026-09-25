"""Crowd providers: where a gym's Popular times reading comes from.

`GoogleMapsProvider` reads the chart off the rendered Google Maps place page. Three things
it needs were each found the hard way (September 2026), and none is optional:

1. A signed-in Google session. Signed-out Maps, incognito included, serves a "limited
   view" with no Popular times section. The session lives in a persistent Chromium
   profile (`Settings.scrape_profile_dir`), created once by `open_login_window`.
2. A desktop user agent. Even signed in, a `HeadlessChrome` user agent gets the limited
   view; the same UA with `Chrome` in its place gets the chart.
3. Full Chromium (`channel="chromium"`), not Playwright's default headless shell.

Playwright's sync API is bound to the thread that started it, so the provider owns one
worker thread and runs every browser call on it; `asyncio.to_thread` would hop threads.
"""

import asyncio
import logging
import subprocess
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from types import TracebackType
from typing import Any, Protocol, Self, TypeVar
from urllib.parse import quote_plus

from playwright.sync_api import BrowserContext, Page, Playwright, sync_playwright
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

from app.db import models as db
from app.scrape.parse import CrowdReading, NoChartData, RawChart, parse_chart
from app.services.busyness import local_slot

logger = logging.getLogger(__name__)

T = TypeVar("T")

LOGIN_URL = "https://accounts.google.com/ServiceLogin?continue=https://www.google.com/maps"
REGION = "div[role='region'][aria-label^='Popular times at ']"
MAIN = "div[role='main']"
# The chart lazy-loads as the side panel scrolls; ~9 x 900px reaches it.
SCROLL_STEPS = 9
SCROLL_PX = 900
PLACE_TIMEOUT_MS = 15_000

# Region, header and per-day labels in one round trip. The day containers are the
# children of whichever region child holds the most bars; the parser checks there are 7.
EXTRACT_JS = """
(region_selector) => {
  const placeName = document.querySelector('h1')?.textContent?.trim() || null;
  const region = document.querySelector(region_selector);
  if (!region) return {placeName, header: '', days: []};
  const bars = (el) => el.querySelectorAll('[aria-label*="% busy"]').length;
  let box = null;
  for (const child of region.children) {
    if (bars(child) > (box ? bars(box) : 0)) box = child;
  }
  const days = box ? Array.from(box.children, (day) =>
    Array.from(day.querySelectorAll('[aria-label]'), (el) => el.getAttribute('aria-label'))
  ) : [];
  return {placeName, header: region.innerText, days};
}
"""


class ProviderUnavailable(Exception):
    """The provider cannot fetch any gym right now; stop the run instead of retrying."""


class CrowdProvider(Protocol):
    async def fetch(self, gym: db.Gym, now: datetime) -> CrowdReading:
        """Read one gym's chart. `now` is the poll tick, used to check the day mapping."""
        ...


def search_url(query: str) -> str:
    return f"https://www.google.com/maps/search/{quote_plus(query)}?hl=en"


def desktop_user_agent(headless_user_agent: str) -> str:
    """The same browser and version, without the `HeadlessChrome` marker."""

    return headless_user_agent.replace("HeadlessChrome/", "Chrome/")


def open_login_window(profile_dir: Path) -> int:
    """Open a visible Chromium on `profile_dir` and block until it quits.

    Chromium is started as a plain process, not through Playwright: Google's sign-in page
    rejects browsers under automation ("This browser or app may not be secure"). The
    binary is Playwright's own, so the profile it writes is one the scraper can reopen.

    `--use-mock-keychain` is load-bearing on macOS. Playwright always passes it, and
    Chromium encrypts cookies with the keychain's key: a login window on the real
    Keychain writes a session the headless scraper cannot decrypt, and Maps falls back
    to its signed-out "limited view".
    """

    profile_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        executable = playwright.chromium.executable_path
    command = [
        executable,
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--use-mock-keychain",
        LOGIN_URL,
    ]
    return subprocess.run(command, check=False).returncode


def launch_profile_context(playwright: Playwright, profile_dir: Path) -> BrowserContext:
    """A headless browser context on the signed-in profile, with a desktop user agent."""

    if not profile_dir.is_dir():
        raise ProviderUnavailable(
            f"No browser profile at {profile_dir}; run `python -m app.scrape --login` first"
        )
    # A throwaway launch to learn this Chromium's own UA, so the override tracks upgrades.
    probe = playwright.chromium.launch(channel="chromium", headless=True)
    try:
        user_agent = desktop_user_agent(probe.new_page().evaluate("navigator.userAgent"))
    finally:
        probe.close()
    return playwright.chromium.launch_persistent_context(
        profile_dir,
        channel="chromium",
        headless=True,
        locale="en-US",
        viewport={"width": 1280, "height": 900},
        user_agent=user_agent,
    )


def load_chart(page: Page, url: str) -> RawChart:
    """Navigate to a place and extract its chart. Raises `NoChartData` on a stunted load."""

    page.goto(url, wait_until="domcontentloaded")
    if "/maps/place/" not in url:
        try:
            page.wait_for_url("**/maps/place/**", timeout=PLACE_TIMEOUT_MS)
        except PlaywrightTimeoutError as error:
            raise NoChartData("the search did not open a single place page") from error
    page.wait_for_selector(MAIN)
    if page.evaluate("/limited view of Google Maps/i.test(document.body.innerText)"):
        raise ProviderUnavailable(
            "Google Maps served its signed-out limited view; the session in the scrape "
            "profile has expired. Run `python -m app.scrape --login` again."
        )

    for _ in range(SCROLL_STEPS):
        if page.query_selector(REGION):
            break
        page.mouse.move(200, 500)
        page.mouse.wheel(0, SCROLL_PX)
        page.wait_for_timeout(400)

    data: dict[str, Any] = page.evaluate(EXTRACT_JS, REGION)
    return RawChart(
        place_name=data["placeName"],
        header=data["header"],
        days=tuple(tuple(labels) for labels in data["days"]),
    )


class GoogleMapsProvider:
    """Reads Popular times through one shared browser. Use as `async with`."""

    def __init__(self, profile_dir: Path, *, max_attempts: int) -> None:
        self._profile_dir = profile_dir
        self._max_attempts = max_attempts
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="playwright")
        self._playwright: Playwright | None = None
        self._context: BrowserContext | None = None

    async def __aenter__(self) -> Self:
        await self._call(self._start)
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        try:
            await self._call(self._stop)
        finally:
            self._executor.shutdown(wait=True)

    async def fetch(self, gym: db.Gym, now: datetime) -> CrowdReading:
        url = gym.google_maps_url or search_url(gym.google_maps_query)
        today, _ = local_slot(now, gym.timezone)
        return await self._call(lambda: self._fetch(url, today))

    async def _call(self, fn: Callable[[], T]) -> T:
        return await asyncio.get_running_loop().run_in_executor(self._executor, fn)

    def _start(self) -> None:
        self._playwright = sync_playwright().start()
        try:
            self._context = launch_profile_context(self._playwright, self._profile_dir)
        except BaseException:
            self._stop()
            raise

    def _stop(self) -> None:
        if self._context is not None:
            self._context.close()
            self._context = None
        if self._playwright is not None:
            self._playwright.stop()
            self._playwright = None

    def _fetch(self, url: str, today: int) -> CrowdReading:
        """Load and parse, retrying stunted loads up to `max_attempts` times."""

        if self._context is None:
            raise RuntimeError("GoogleMapsProvider is used outside `async with`")
        page = self._context.new_page()
        try:
            for attempt in range(1, self._max_attempts + 1):
                try:
                    return parse_chart(load_chart(page, url), today=today)
                except (NoChartData, PlaywrightTimeoutError) as error:
                    logger.info("attempt %d/%d: %s", attempt, self._max_attempts, error)
            raise NoChartData(f"no Popular times bars after {self._max_attempts} attempts")
        finally:
            page.close()
