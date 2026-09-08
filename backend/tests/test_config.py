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
