"""Application settings, loaded from the environment (or a local `.env`)."""

from functools import lru_cache
from urllib.parse import urlsplit

from pydantic import field_validator
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
    mapbox_token: str = ""

    # --- Ingestion ------------------------------------------------------
    live_poll_minutes: int = 20
    curve_poll_hours: int = 24
    scrape_max_attempts: int = 6

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

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    """Cached accessor so settings are parsed once per process."""
    return Settings()
