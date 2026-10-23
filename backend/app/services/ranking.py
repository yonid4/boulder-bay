"""Ranking score and the per-user weights behind it.

`score()` is a plain function -- no SQL, no clock -- so the formula is unit-testable:

    crowd = 0 if closed else (busy_pct if known else 50)
    score = 100
          - w_crowd  * crowd
          - w_travel * min(travel_minutes, travel_cap_minutes)
          + member_boost   if member
          - closed_penalty if closed

With the default weights this is the mockup's formula. Ordering and rounding belong to
the caller. Unknown busyness while open counts as 50 (the middle of Moderate): treating
it as 0 would make a scraper gap look like the best gym in the Bay.
"""

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import models as db

# A presentation offset, not a tunable (schema 2.8).
BASE_SCORE = 100.0
UNKNOWN_BUSY_PCT = 50.0


@dataclass(frozen=True)
class RankingWeights:
    w_crowd: float
    w_travel: float
    member_boost: float
    closed_penalty: float
    travel_cap_minutes: int

    @classmethod
    def from_prefs(cls, prefs: db.RankingPrefs) -> "RankingWeights":
        return cls(
            w_crowd=float(prefs.w_crowd),
            w_travel=float(prefs.w_travel),
            member_boost=float(prefs.member_boost),
            closed_penalty=float(prefs.closed_penalty),
            travel_cap_minutes=prefs.travel_cap_minutes,
        )


# Mirrors the `ranking_prefs` column defaults, i.e. the prototype formula.
DEFAULT_WEIGHTS = RankingWeights(
    w_crowd=0.6, w_travel=0.5, member_boost=15.0, closed_penalty=60.0, travel_cap_minutes=60
)


def score(
    *,
    busy_pct: float | None,
    is_open: bool,
    travel_minutes: float,
    is_member: bool,
    weights: RankingWeights = DEFAULT_WEIGHTS,
) -> float:
    """Score one gym; higher is a better pick. Returned unrounded."""

    if not is_open:
        crowd = 0.0
    elif busy_pct is None:
        crowd = UNKNOWN_BUSY_PCT
    else:
        crowd = busy_pct
    travel = min(travel_minutes, weights.travel_cap_minutes)

    result = BASE_SCORE - weights.w_crowd * crowd - weights.w_travel * travel
    if is_member:
        result += weights.member_boost
    if not is_open:
        result -= weights.closed_penalty
    return result


async def get_or_create_ranking_prefs(session: AsyncSession, user_id: UUID) -> db.RankingPrefs:
    """The user's prefs row, created with the column defaults on first use.

    `INSERT ... ON CONFLICT DO NOTHING` then `SELECT`, so concurrent first requests
    cannot collide. The caller owns the transaction.
    """

    await session.execute(
        pg_insert(db.RankingPrefs).values(user_id=user_id).on_conflict_do_nothing()
    )
    result = await session.scalars(
        select(db.RankingPrefs).where(db.RankingPrefs.user_id == user_id)
    )
    return result.one()
