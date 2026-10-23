"""add saved location kind

Revision ID: 75ffc45ed87e
Revises: b91e4d2c7a60
Create Date: 2026-10-22 12:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


# revision identifiers, used by Alembic.
revision: str = "75ffc45ed87e"
down_revision: Union[str, Sequence[str], None] = "b91e4d2c7a60"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Tag each saved location home / work / other, with at most one home and one work.

    The server default backfills existing rows as `other`, which carries no special
    meaning. The two partial unique indexes are matched by name in the API to give a
    second home or work its own 409 message.
    """
    op.add_column(
        "saved_locations",
        sa.Column("kind", sa.Text(), server_default=sa.text("'other'"), nullable=False),
    )
    op.create_check_constraint(
        "saved_locations_kind_valid",
        "saved_locations",
        "kind in ('home', 'work', 'other')",
    )
    op.create_index(
        "saved_locations_one_home_idx",
        "saved_locations",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("kind = 'home'"),
    )
    op.create_index(
        "saved_locations_one_work_idx",
        "saved_locations",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("kind = 'work'"),
    )


def downgrade() -> None:
    """Drop the kind column along with its check constraint and indexes."""
    op.drop_index("saved_locations_one_work_idx", table_name="saved_locations")
    op.drop_index("saved_locations_one_home_idx", table_name="saved_locations")
    op.drop_constraint("saved_locations_kind_valid", "saved_locations", type_="check")
    op.drop_column("saved_locations", "kind")
