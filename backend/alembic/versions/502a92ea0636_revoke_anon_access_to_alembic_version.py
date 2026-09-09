"""revoke anon access to alembic_version

Alembic creates `alembic_version` itself, before any revision runs, so it picks up
Supabase's default privileges for new tables in `public` the same way an application
table would -- and it is the one table 7bea7599f868's revoke block does not cover,
because it is not ours to list.

The grants are REFERENCES, TRIGGER and TRUNCATE. No SELECT, so nothing leaks through
PostgREST, but TRUNCATE would let any anonymous holder of the bundled anon key empty
the table -- after which Alembic reads the database as being at base and would try to
re-run every migration from scratch. TRIGGER is nearly as bad.

RLS is deliberately not enabled here, unlike the nine application tables. The grants
are what PostgREST acts on; with none, RLS would be redundant, and enabling it on a
table Alembic owns and writes on every migration buys nothing for the risk.

Revision ID: 502a92ea0636
Revises: b00fd69a53b6
Create Date: 2026-09-08 19:42:02.013803

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '502a92ea0636'
down_revision: Union[str, Sequence[str], None] = 'b00fd69a53b6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("revoke all on public.alembic_version from anon, authenticated")


def downgrade() -> None:
    """Deliberately a no-op.

    Downgrading should not hand an anonymous role TRUNCATE on the migration ledger
    back. Re-grant by hand if some future setup genuinely needs it.
    """
