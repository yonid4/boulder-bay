# Boulder Bay — backend

FastAPI backend, Python >=3.11, dependencies managed with `uv` (`pyproject.toml` + `uv.lock`).

## Run
```
uv run uvicorn app.main:app --reload
```
Serves on localhost; `GET /health` returns `{"status": "ok"}`.

## Structure
- `app/main.py` — FastAPI entrypoint (`app = FastAPI(...)`), currently only exposes `/health`.
- `app/__init__.py` — package marker.

## Conventions
- Use `uv add <package>` / `uv sync` to manage dependencies — don't hand-edit `uv.lock` or use `pip` directly.
- Ruff is the linter in use (`.ruff_cache/` present, gitignored).
- `.venv/` is gitignored — always run Python via `uv run ...` rather than assuming an activated venv.

## Planned but not yet implemented
Per `../boulder_bay_plan.md`, the following are decided for v1 but not yet built — don't assume they exist:
- Supabase (Postgres) with PostGIS enabled, for storage and the straight-line distance pre-filter.
- APScheduler running inside the FastAPI process, driving a Playwright headless-browser scrape of Google Maps for live/historical crowd data.
- Mapbox Matrix API calls for travel time on the narrowed candidate gym set.
- Supabase Auth for sign-up/login.
