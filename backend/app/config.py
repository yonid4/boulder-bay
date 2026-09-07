"""Application settings, loaded from the environment (or a local `.env`)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- Database -------------------------------------------------------
    # Supabase's direct Postgres connection is IPv6-only; use the Supavisor
    # session-mode pooler (port 5432) so asyncpg keeps prepared statements.
    database_url: str = "postgresql+asyncpg://postgres:postgres@127.0.0.1:54322/postgres"

    # --- Supabase Auth --------------------------------------------------
    # JWTs are ES256, verified against {supabase_url}/auth/v1/.well-known/jwks.json.
    supabase_url: str = "http://127.0.0.1:54321"
    supabase_anon_key: str = ""

    # --- Routing --------------------------------------------------------
    mapbox_token: str = ""

    # --- Ingestion ------------------------------------------------------
    live_poll_minutes: int = 20
    curve_poll_hours: int = 24
    scrape_max_attempts: int = 6

    @property
    def jwks_url(self) -> str:
        return f"{self.supabase_url}/auth/v1/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    """Cached accessor so settings are parsed once per process."""
    return Settings()
