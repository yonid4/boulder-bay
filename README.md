# Boulder Bay

An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

Monorepo with two parts:
- `backend/` — FastAPI (Python), managed with `uv`
- `app/` — React Native / Expo (TypeScript), managed with `npm`

See `boulder_bay_plan.md` for the full project plan, and `CLAUDE.md` / `backend/CLAUDE.md` for AI-assistant context.

## Prerequisites & Requirements
- **Python** >= 3.11
- [**uv**](https://docs.astral.sh/uv/) for Python dependency management
- **Node.js** (LTS) and **npm**
- **Xcode** with an iOS Simulator (native `ios/`/`android/` projects are generated via `expo prebuild`, and this app uses a custom Expo dev client since `react-native-maps` requires native code — plain Expo Go will not work)
- A macOS machine, for iOS Simulator/Xcode

## Installation Guide

### Backend
```
cd backend
uv sync
```

### App
```
cd app
npm install
npx expo prebuild
```
`expo prebuild` generates the native `ios/`/`android/` projects (gitignored) needed for the custom dev client.

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
```
cd app
npm run ios
```
This builds the custom dev client and launches it in the iOS Simulator. For subsequent runs without rebuilding native code, you can instead use `npm start` and open the already-built dev client from the simulator.

The iOS Simulator reaches the backend via `localhost`; a physical device should use your Mac's local network IP over the same Wi-Fi (see `boulder_bay_plan.md` for tunneling fallback options).
