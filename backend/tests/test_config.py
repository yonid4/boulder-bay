from app.config import Settings


def test_jwks_url_is_derived_from_supabase_url() -> None:
    settings = Settings(supabase_url="https://example.supabase.co")
    assert settings.jwks_url == ("https://example.supabase.co/auth/v1/.well-known/jwks.json")


def test_database_url_defaults_to_local_supabase() -> None:
    assert "asyncpg" in Settings().database_url
