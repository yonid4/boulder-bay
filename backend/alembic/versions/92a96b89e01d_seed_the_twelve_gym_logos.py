"""seed the twelve gym logos

The source of truth for the logo bytes, as b00fd69a53b6 is for the gyms themselves.

Reads twelve PNGs from `data/logos/<key>.png` next to this file -- see that directory's
README. They are read at upgrade time rather than embedded as base64 so the files stay
reviewable images in git; the cost is that deleting them breaks a from-scratch replay.

Sixteen gyms, twelve marks: LOGO_BY_SLUG below is where the sharing is decided, once and by
hand. Four Movement gyms point at `movement` and two Benchmark gyms at `benchmark`. This is
the only place that mapping exists -- after this runs it is a foreign key, not a convention.

`gym_logos.id` is `generated always as identity`, so its values are not knowable when this
migration is written; the backfill joins on `key` and `slug` instead, the same shape
b00fd69a53b6's GYM_HOURS_SQL uses.

Revision ID: 92a96b89e01d
Revises: dba1c1f91ed2
Create Date: 2026-09-09 11:44:00.000000

"""
import hashlib
from pathlib import Path
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '92a96b89e01d'
down_revision: Union[str, Sequence[str], None] = 'dba1c1f91ed2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


LOGOS_DIR = Path(__file__).parent / "data" / "logos"

# Every gym slug seeded by b00fd69a53b6 -> the mark it renders. Ten gyms have their own;
# the Movement four and the Benchmark two share a brand-level mark. That `movement` and
# `benchmark` also happen to be `gyms.brand` values is a naming coincidence, not a lookup.
LOGO_BY_SLUG = {
    "mission": "mission",
    "dogpatch": "dogpatch",
    "hyperion": "hyperion",
    "gwpc": "gwpc",
    "pipe": "pipe",
    "ironworks": "ironworks",
    "the-oaks": "the-oaks",
    "studio": "studio",
    "mv-sf": "movement",
    "mv-belmont": "movement",
    "mv-mountain-view": "movement",
    "mv-santa-clara": "movement",
    "bm-sf": "benchmark",
    "bm-berkeley": "benchmark",
    "the-peak": "the-peak",
    "mosaic": "mosaic",
}

# The twelve distinct marks, i.e. the twelve files expected in data/logos/.
LOGO_KEYS = sorted(set(LOGO_BY_SLUG.values()))

# `image` must be bound, not interpolated -- binary cannot be inlined into SQL text.
INSERT_LOGO = sa.text(
    """
    insert into public.gym_logos (key, content_type, image, byte_size, sha256)
    values (:key, 'image/png', :image, :byte_size, :sha256)
    on conflict (key) do nothing
    """
).bindparams(sa.bindparam("image", type_=sa.LargeBinary))

# UPDATE ... FROM: the values list carries the mapping, the join resolves it to logo ids.
BACKFILL_SQL = """
update public.gyms g
set logo_id = l.id
from (values {pairs}) as m(slug, key)
join public.gym_logos l on l.key = m.key
where g.slug = m.slug
"""


def upgrade() -> None:
    """Load the twelve marks, then point all sixteen gyms at them."""
    bind = op.get_bind()

    for key in LOGO_KEYS:
        path = LOGOS_DIR / f"{key}.png"
        if not path.is_file():
            raise RuntimeError(
                f"missing logo seed file {path}. The twelve PNGs in data/logos/ are this "
                f"revision's source data; restore them from git before upgrading."
            )
        image = path.read_bytes()
        bind.execute(
            INSERT_LOGO,
            {
                "key": key,
                "image": image,
                "byte_size": len(image),
                "sha256": hashlib.sha256(image).hexdigest(),
            },
        )

    pairs = ", ".join(f"('{slug}', '{key}')" for slug, key in LOGO_BY_SLUG.items())
    result = bind.execute(sa.text(BACKFILL_SQL.format(pairs=pairs)))

    # A short count means a slug here disagrees with the seeded gym set -- fail loudly
    # rather than leaving some gyms with a NULL logo_id and no indication why.
    if result.rowcount != len(LOGO_BY_SLUG):
        raise RuntimeError(
            f"expected to point {len(LOGO_BY_SLUG)} gyms at a logo, updated {result.rowcount}"
        )


def downgrade() -> None:
    """Remove only the twelve seeded marks.

    Scoped by key rather than truncating, so a logo added later by hand survives. The
    foreign key is ON DELETE SET NULL, so `gyms.logo_id` clears itself as these go.
    """
    keys = ", ".join(f"'{key}'" for key in LOGO_KEYS)
    op.execute(f"delete from public.gym_logos where key in ({keys})")
