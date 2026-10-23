"""Application settings, loaded from the environment (or a local `.env`)."""

from functools import lru_cache
from pathlib import Path
from urllib.parse import urlsplit

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Supavisor's transaction-mode port. asyncpg's prepared statements don't survive
# it — using it would force `statement_cache_size=0` + `NullPool`.
TRANSACTION_POOLER_PORT = 6543


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- Database -------------------------------------------------------
    # Required: there is no local Postgres to fall back to. Copy the connection
    # string from Supabase → Project Settings → Database, take the SESSION-mode
    # pooler (port 5432), and swap the scheme for `postgresql+asyncpg://`.
    database_url: str

    # --- Supabase Auth --------------------------------------------------
    # JWTs are ES256, verified against {supabase_url}/auth/v1/.well-known/jwks.json.
    supabase_url: str

    # Only needed if the backend ever calls Supabase's own REST/Auth API. The
    # iOS app carries its own copy for supabase-swift.
    supabase_anon_key: str = ""

    # --- Routing --------------------------------------------------------
    # Empty means every travel time is the haversine fallback (6 + miles x 2.3).
    mapbox_token: str = ""
    # Straight-line prefilter for rankings: gyms farther than this aren't ranked. 50 mi.
    ranking_radius_meters: int = Field(default=80_467, gt=0)

    # --- /health --------------------------------------------------------
    # How long /health waits on the database before naming a cause. A connection not made
    # in time is "unreachable"; Postgres's lock_timeout firing is "locked", its
    # statement_timeout firing is "overloaded". The total caps the whole check, so /health
    # answers even when the server never replies.
    health_connect_timeout_seconds: float = Field(default=2.0, gt=0)
    health_lock_timeout_ms: int = Field(default=1_000, gt=0)
    health_statement_timeout_ms: int = Field(default=2_000, gt=0)
    health_total_timeout_seconds: float = Field(default=3.0, gt=0)

    # --- Ingestion ------------------------------------------------------
    live_poll_minutes: int = 30
    scrape_max_attempts: int = 6
    # Run the half-hourly poll inside the API process. Off by default so tests, CI and a
    # plain dev server never launch Chromium.
    scheduler_enabled: bool = False
    # Chromium profile holding a signed-in Google session; signed-out Maps hides Popular
    # times. It is a live credential, so it lives outside the repo by default.
    scrape_profile_dir: Path = Path.home() / ".boulder-bay" / "chromium-profile"

    @field_validator("database_url")
    @classmethod
    def _reject_known_bad_connection_strings(cls, value: str) -> str:
        """Catch the two connection mistakes this project has already paid for."""
        if "+asyncpg" not in value:
            raise ValueError(
                "DATABASE_URL must name the asyncpg driver, e.g. "
                "postgresql+asyncpg://... (SQLAlchemy defaults to psycopg2 otherwise)"
            )
        if f":{TRANSACTION_POOLER_PORT}/" in value:
            raise ValueError(
                f"Port {TRANSACTION_POOLER_PORT} is Supavisor's transaction-mode pooler, "
                "which breaks asyncpg prepared statements. Use the session-mode "
                "pooler on port 5432 instead."
            )
        return value

    @field_validator("supabase_url")
    @classmethod
    def _require_https(cls, value: str) -> str:
        """Supabase is HTTPS-only; an `http://` URL fails at the JWKS fetch."""
        host = urlsplit(value).hostname or ""
        if not value.startswith("https://") and host not in {"localhost", "127.0.0.1"}:
            raise ValueError(f"SUPABASE_URL must start with https:// (got {value!r})")
        return value.rstrip("/")

    @field_validator("scrape_profile_dir")
    @classmethod
    def _expand_home(cls, value: Path) -> Path:
        """`~` in `.env` is literal text to pydantic; Chromium needs a real path."""
        return value.expanduser()

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    """Cached accessor so settings are parsed once per process."""
    return Settings()
