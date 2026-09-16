"""require profile display names

Revision ID: 4f8c2d1a9b73
Revises: 92a96b89e01d
Create Date: 2026-09-15 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "4f8c2d1a9b73"
down_revision: Union[str, Sequence[str], None] = "92a96b89e01d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Require a normalized display name on every application profile."""
    op.alter_column("profiles", "display_name", existing_type=sa.Text(), nullable=False)
    op.create_check_constraint(
        "profiles_display_name_trimmed",
        "profiles",
        "display_name = regexp_replace(display_name, "
        "'^[[:space:]]+|[[:space:]]+$', '', 'g')",
    )
    op.create_check_constraint(
        "profiles_display_name_length",
        "profiles",
        "char_length(display_name) between 1 and 80",
    )


def downgrade() -> None:
    """Restore the nullable, unconstrained display-name column."""
    op.drop_constraint("profiles_display_name_length", "profiles", type_="check")
    op.drop_constraint("profiles_display_name_trimmed", "profiles", type_="check")
    op.alter_column("profiles", "display_name", existing_type=sa.Text(), nullable=True)
