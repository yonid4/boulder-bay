# Boulder Bay

An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

Monorepo with two parts:
- `backend/` — FastAPI (Python), managed with `uv`
- `app/` — native SwiftUI iOS app (Xcode project not yet added — see `boulder_bay_plan.md`)

See `boulder_bay_plan.md` for the full project plan, and `CLAUDE.md` / `backend/CLAUDE.md` for AI-assistant context.

## Prerequisites & Requirements
- **Python** >= 3.11
- [**uv**](https://docs.astral.sh/uv/) for Python dependency management
- **Xcode** with an iOS Simulator
- A macOS machine, for iOS Simulator/Xcode

## Installation Guide

### Backend
```
cd backend
uv sync
```

### App
The native SwiftUI app has not been scaffolded yet. See `boulder_bay_plan.md` for the planned iOS stack.

## Usage Examples (Quick Start)

### Run the backend
```
cd backend
uv run uvicorn app.main:app --reload
```
Verify it's up:
```
curl http://localhost:8000/health
# {"status":"ok"}
```

### Run the app
Not available yet — the Xcode project has not been created. Once it exists, build and run it from Xcode.

The iOS Simulator reaches the backend via `localhost`; a physical device should use your Mac's local network IP over the same Wi-Fi (see `boulder_bay_plan.md` for tunneling fallback options).
