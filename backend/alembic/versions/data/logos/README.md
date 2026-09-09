# Gym logo seed source

The twelve PNGs in this directory are the seed source for the `gym_logos` table. The seed
revision reads them **by filename** — each file's stem is the `gym_logos.key` it becomes —
so renaming or deleting one breaks a from-scratch `alembic upgrade head`.

These are a one-time seed source, never a serving path. Once the migration has run, nothing
reads them again: the bytes live in Postgres and the API serves them from there.

Ten are per-gym marks; `movement.png` and `benchmark.png` are brand-level, shared by the four
Movement and two Benchmark gyms respectively. All twelve are 512x512, black-on-transparent
(Movement's teal and Mosaic's orange preserved), wordmarks cropped except The Peak of Fremont,
which keeps its trademark.

They are committed because that hand-processing is not reproducible — see
`boulder_bay_schema.md` §7. Delete them only once logos arrive through an ingestion path
rather than through this seed.
