# Boulder Bay — Project Plan (v1)
*(working title through planning: "Boulder Gym Crowd Watcher")*

## One-liner
An app that shows Bay Area bouldering gyms, how busy each one currently is, the best time to climb at each, and which gym is the best pick right now based on your location and how crowded each option is.

## Motivation
- No Bay Area gym chain (Movement, Touchstone) currently publishes live occupancy on their own site — Google's popular-times data is the only source with coverage across all of them.
- Personal need: decide where to climb, and when, without guessing.
- Resume goal: a backend-flavored personal project (data ingestion, polling, ranking logic) that doesn't lean on an LLM.

## Users & Access
- Not a public release for v1.
- Sign-up + login in the UI, so you (and anyone testing with you) can create accounts directly rather than needing manual invites — easier for testing across different areas/gyms beyond just the ones near you.

## Scope for v1
**In scope:**
- Fixed, curated list of Bay Area bouldering gyms (Movement locations, Touchstone locations, any independents worth including) — not a general "search any city" tool.
- Live busyness per gym.
- Best time to climb, per gym (based on historical patterns, not just live data).
- "Best gym for me right now" ranking.
- Mark which gyms you're a member of, so those are boosted/prioritized in the ranking.
- Location input: a set home location plus a couple of other saved spots (e.g. work, a friend's place) — you pick which one you're located at.

**Out of scope for v1:**
- Real-time GPS/device location (planned for later).
- Gyms outside the Bay Area / general gym discovery.
- Public sign-up or public release.
- Usage-based clustering priority (a per-user, per-gym view counter to factor "gyms you check most" into map clustering) — deferred to v2; clustering priority is membership-only for v1.

## Core Features
1. **Gym list/map view** — see all tracked gyms and where they are.
2. **Live busyness** — current crowd level per gym.
3. **Best time to climb** — a per-gym recommendation based on historical crowd patterns, not just a single live reading.
4. **"Best gym right now" ranking** — combines:
   - Distance from your selected location, within an acceptable buffer (e.g. "gyms within X extra minutes of the closest one" rather than only the single nearest gym)
   - Current/predicted crowd level (least busy ranks higher)
   - Membership boost — gyms you've marked as "I'm a member here" get prioritized over ones you'd have to pay a day-rate for
5. **Location switcher** — toggle between home and saved spots to see rankings from each.
6. **Gym detail screen** — reached by tapping a gym from the map or Rankings. Shows:
   - Logo and name
   - Address — tappable, opens Maps/Google Maps
   - Hours
   - Busyness — live, plus an optional prediction for the rest of the day until closing
   - Info such as rates
   - Waiver link, if the gym has one
   - Website link

## UI Structure (v1)
Bottom tab navigation, three tabs:
- **Map** — full-screen map; gym pins show a busyness bar when zoomed in, and zoomed-out clusters surface the higher-priority gym(s) based on membership
- **Rankings** — the "best gym right now" list, using the ranking formula above
- **Settings** — profile, sign out, and the gym membership list

Map and Rankings both open the same **Gym detail** screen (see Core Features) when a gym is tapped — it's a shared destination, not its own tab.

## Key Decisions Made So Far
- **Auth**: sign-up + login, self-serve in the UI — makes it easy to create test accounts yourself rather than manually provisioning invites. Still not a public release, just not gated behind manual account creation.
- **Gym set**: fixed, hand-curated Bay Area list for v1.
- **Ranking formula**: two-stage distance filtering — straight-line distance narrows the candidate gyms first, then actual travel time is computed only for that narrowed set, to avoid running routing calls on every gym. Default weighting: crowd level matters more than travel time, and membership status gives a strong boost that pushes gyms you belong to near the top. Weights are user-configurable, not hardcoded.
- **Location handling**: manually selected from a small set of saved locations (home + a couple others) for now; real-time GPS deferred.
- **Data source**: Google's (unofficial) popular-times data, for now — accepted as the primary source across all gyms despite the reliability caveat below. Individual gyms can still be checked later for a native occupancy widget as a possible cleaner override.
- **Gym list maintenance**: manual — edited by hand as gyms open, close, or rebrand.

## Accepted Risk
- **Data reliability**: the popular-times data isn't officially supported by Google, so it could change or break without warning. Accepted for now since the project isn't being publicly released or depended on.

## Technical Stack (v1)

**Platform**: native iOS app, tested via Xcode on your own device to start.

**Backend**
- FastAPI + Python 3, run locally during development (hosting deferred — see below)
- Supabase (Postgres), with the PostGIS extension enabled for the straight-line distance pre-filter
- APScheduler, running inside the FastAPI process, for the recurring `populartimes` polling job

**Data ingestion**
- Crowd data: `populartimes` (open-source, MIT licensed) for current + historical popularity — chosen over Apify's paid Google Maps Scraper to keep recurring cost at zero and keep the ingestion pipeline as something you own and can speak to
- Requires a Google Cloud project + Places API key for a one-time per-gym place ID/metadata lookup; the popularity data itself isn't billed by Google
- Per-gym override: a native occupancy widget, for any gym that happens to expose one (checked individually, not assumed)

**Routing**
- Mapbox Matrix API for travel time on the narrowed candidate set — chosen over Google Routes API and TravelTime for its larger free tier and no card required to start

**Mobile app**
- React Native via Expo, TypeScript
- Expo Router for navigation (file-based, like Next.js App Router)
- `react-native-maps` for the gym map view
- Zustand + TanStack Query for state/data-fetching, same pattern as When.
- Custom Expo dev client (via EAS Build), since `react-native-maps` needs native code outside plain Expo Go

**Auth**
- Sign-up + login, self-serve in the UI; Supabase Auth is the likely default since Supabase is already in the stack

**iOS distribution**
- Free Apple ID / Personal Team for building and running on your own device via Xcode
- Apple Developer Program ($99/year) deferred until painless TestFlight sharing beyond a small, physically-reachable friend group is needed

**Local development**
- FastAPI run locally — iOS Simulator hits it via localhost, your physical device via your Mac's local network IP over the same Wi-Fi
- A tunneling tool (ngrok / Cloudflare Tunnel) as a fallback for testing across networks, without deploying anywhere

## Deferred for Later
- **Long-term hosting**: where FastAPI actually runs once local + tunnel testing isn't enough. Not worth deciding yet.

## Next Step
Stack decisions are locked in for v1, including the background scheduler. Start implementation with schema design and the FastAPI + populartimes ingestion piece.
