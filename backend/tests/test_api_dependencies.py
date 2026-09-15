from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jwt import PyJWKClientConnectionError, PyJWKClientError

from app.api import dependencies

SUPABASE_URL = "https://example.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
USER_ID = UUID("0e17b0e8-660c-46ef-ab9f-c4d91340809d")


class FakeSettings:
    supabase_url = SUPABASE_URL


class FakeJWKClient:
    def __init__(self, key: object | None = None, error: Exception | None = None) -> None:
        self.key = key
        self.error = error

    def get_signing_key_from_jwt(self, token: str) -> object:
        if self.error is not None:
            raise self.error
        assert self.key is not None
        return self.key


@pytest.fixture
def private_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def make_token(
    private_key: ec.EllipticCurvePrivateKey,
    *,
    include_expiration: bool = True,
    **overrides: Any,
) -> str:
    claims: dict[str, Any] = {
        "sub": str(USER_ID),
        "iss": ISSUER,
        "aud": "authenticated",
    }
    if include_expiration:
        claims["exp"] = datetime.now(UTC) + timedelta(minutes=5)
    claims.update(overrides)
    return jwt.encode(claims, private_key, algorithm="ES256", headers={"kid": "test-key"})


def configure_verifier(
    monkeypatch: pytest.MonkeyPatch,
    *,
    key: object | None = None,
    error: Exception | None = None,
) -> None:
    client = FakeJWKClient(key=key, error=error)
    monkeypatch.setattr(dependencies, "get_settings", lambda: FakeSettings())
    monkeypatch.setattr(dependencies, "get_jwks_client", lambda: client)


def credentials(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


async def test_valid_supabase_token_returns_authenticated_user(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    configure_verifier(monkeypatch, key=private_key.public_key())

    user = await dependencies.require_user(credentials(make_token(private_key)))

    assert user.id == USER_ID


@pytest.mark.parametrize(
    ("overrides"),
    [
        {"iss": "https://another-project.supabase.co/auth/v1"},
        {"aud": "anon"},
        {"exp": datetime.now(UTC) - timedelta(minutes=1)},
        {"sub": "not-a-uuid"},
    ],
    ids=["wrong-issuer", "wrong-audience", "expired", "invalid-subject"],
)
async def test_invalid_claims_are_rejected(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
    overrides: dict[str, Any],
) -> None:
    configure_verifier(monkeypatch, key=private_key.public_key())

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(credentials(make_token(private_key, **overrides)))

    assert caught.value.status_code == 401
    assert caught.value.detail == dependencies.INVALID_TOKEN_DETAIL
    assert caught.value.headers == {"WWW-Authenticate": "Bearer"}


async def test_token_signed_by_another_key_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    untrusted_key = ec.generate_private_key(ec.SECP256R1())
    configure_verifier(monkeypatch, key=private_key.public_key())

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(credentials(make_token(untrusted_key)))

    assert caught.value.status_code == 401


async def test_token_without_expiration_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    configure_verifier(monkeypatch, key=private_key.public_key())

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(
            credentials(make_token(private_key, include_expiration=False))
        )

    assert caught.value.status_code == 401


async def test_non_es256_token_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    configure_verifier(monkeypatch, key=private_key.public_key())
    token = jwt.encode(
        {
            "sub": str(USER_ID),
            "iss": ISSUER,
            "aud": "authenticated",
            "exp": datetime.now(UTC) + timedelta(minutes=5),
        },
        "not-the-supabase-signing-key-at-least-32-bytes",
        algorithm="HS256",
        headers={"kid": "test-key"},
    )

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(credentials(token))

    assert caught.value.status_code == 401


async def test_unknown_signing_key_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    configure_verifier(monkeypatch, error=PyJWKClientError("No matching signing key"))

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(credentials(make_token(private_key)))

    assert caught.value.status_code == 401


async def test_jwks_connection_failure_is_temporarily_unavailable(
    monkeypatch: pytest.MonkeyPatch,
    private_key: ec.EllipticCurvePrivateKey,
) -> None:
    configure_verifier(monkeypatch, error=PyJWKClientConnectionError("JWKS unavailable"))

    with pytest.raises(HTTPException) as caught:
        await dependencies.require_user(credentials(make_token(private_key)))

    assert caught.value.status_code == 503
    assert caught.value.detail == "Authentication service unavailable"
