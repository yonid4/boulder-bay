"""restrict profile display name characters

Revision ID: b91e4d2c7a60
Revises: 4f8c2d1a9b73
Create Date: 2026-09-15 16:40:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "b91e4d2c7a60"
down_revision: Union[str, Sequence[str], None] = "4f8c2d1a9b73"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Limit profile display names to ASCII letters and spaces."""
    op.create_check_constraint(
        "profiles_display_name_format",
        "profiles",
        "display_name ~ '^[A-Za-z ]+$'",
    )


def downgrade() -> None:
    """Allow any characters accepted by the remaining name constraints."""
    op.drop_constraint("profiles_display_name_format", "profiles", type_="check")
