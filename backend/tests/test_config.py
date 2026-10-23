from pathlib import Path

import pytest
from pydantic import ValidationError

from app.config import Settings

SESSION_POOLER_URL = (
    "postgresql+asyncpg://postgres.abcdefgh:pw@aws-0-us-west-1.pooler.supabase.com:5432/postgres"
)


def make_settings(**overrides: str) -> Settings:
    """Build Settings without depending on a `.env` being present."""
    values: dict[str, str] = {
        "database_url": SESSION_POOLER_URL,
        "supabase_url": "https://example.supabase.co",
        **overrides,
    }
    return Settings(**values)  # type: ignore[arg-type]


def test_jwks_url_is_derived_from_supabase_url() -> None:
    settings = make_settings(supabase_url="https://example.supabase.co")
    assert settings.jwks_url == "https://example.supabase.co/auth/v1/.well-known/jwks.json"


def test_accepts_session_mode_pooler_url() -> None:
    assert make_settings().database_url == SESSION_POOLER_URL


def test_rejects_url_without_asyncpg_driver() -> None:
    plain = SESSION_POOLER_URL.replace("postgresql+asyncpg://", "postgresql://")
    with pytest.raises(ValidationError, match="asyncpg"):
        make_settings(database_url=plain)


def test_rejects_transaction_mode_pooler_port() -> None:
    transaction_mode = SESSION_POOLER_URL.replace(":5432/", ":6543/")
    with pytest.raises(ValidationError, match="session-mode"):
        make_settings(database_url=transaction_mode)


def test_rejects_plain_http_supabase_url() -> None:
    with pytest.raises(ValidationError, match="https"):
        make_settings(supabase_url="http://example.supabase.co")


def test_strips_trailing_slash_so_jwks_url_stays_well_formed() -> None:
    settings = make_settings(supabase_url="https://example.supabase.co/")
    assert settings.jwks_url == "https://example.supabase.co/auth/v1/.well-known/jwks.json"


def test_scrape_profile_dir_expands_home() -> None:
    settings = make_settings(scrape_profile_dir="~/profile")
    assert settings.scrape_profile_dir == Path.home() / "profile"


def test_scrape_profile_dir_defaults_outside_the_repo() -> None:
    assert make_settings().scrape_profile_dir == Path.home() / ".boulder-bay" / "chromium-profile"


def test_ranking_radius_defaults_to_fifty_miles() -> None:
    assert make_settings().ranking_radius_meters == 80_467


def test_ranking_radius_must_be_positive() -> None:
    with pytest.raises(ValidationError, match="greater than 0"):
        make_settings(ranking_radius_meters="0")


def test_health_timeouts_defaults() -> None:
    settings = make_settings()
    assert settings.health_connect_timeout_seconds == 5.0
    assert settings.health_lock_timeout_ms == 1000
    assert settings.health_statement_timeout_ms == 2000
    assert settings.health_total_timeout_seconds == 8.0


@pytest.mark.parametrize(
    "field",
    [
        "health_connect_timeout_seconds",
        "health_lock_timeout_ms",
        "health_statement_timeout_ms",
        "health_total_timeout_seconds",
    ],
)
def test_health_timeouts_must_be_positive(field: str) -> None:
    with pytest.raises(ValidationError, match=field):
        make_settings(**{field: "0"})


def test_log_level_defaults_to_info_and_accepts_lowercase() -> None:
    assert make_settings().log_level == "INFO"
    assert make_settings(log_level="debug").log_level == "DEBUG"


def test_rejects_an_unknown_log_level() -> None:
    with pytest.raises(ValidationError):
        make_settings(log_level="loud")
