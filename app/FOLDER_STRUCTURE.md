# Boulder Bay — iOS App Folder Structure

Target layout for `app/BoulderBay`. The folders are scaffolded; the files are
filled in as screens land — see "Current state" below for what exists today.
See root `CLAUDE.md` for nav structure and `boulder_bay_plan.md` for the
feature spec this implements.

## Tree

```
app/
├── project.yml                          # info.path → Resources/Info.plist; excludes **/.gitkeep
│
├── BoulderBay/
│   ├── App/
│   │   ├── BoulderBayApp.swift          # @main, builds AppContainer, injects into environment
│   │   ├── AppContainer.swift           # composition root: APIClient, AuthService, the three stores
│   │   ├── RootView.swift               # three-way gate — see "Auth & location gate" below
│   │   └── AppRoute.swift               # shared destinations: .map, .rankings, .gyms, .gymDetail(id)
│   │
│   ├── Core/
│   │   ├── Configuration/
│   │   │   └── AppConfig.swift          # existing
│   │   ├── Networking/
│   │   │   ├── APIClient.swift          # generic get/post/delete over URLSession
│   │   │   ├── APIError.swift
│   │   │   ├── APIEnvelope.swift
│   │   │   ├── AuthenticatedRequest.swift   # attaches the Supabase JWT
│   │   │   └── Endpoints/
│   │   │       ├── APIClient+Gyms.swift     # list, detail
│   │   │       ├── APIClient+Rankings.swift
│   │   │       └── APIClient+Me.swift       # profile, saved location, memberships, prefs
│   │   ├── Auth/
│   │   │   └── AuthService.swift        # wraps supabase-swift; @Observable session, sign-in/up/out
│   │   ├── State/                       # app-wide @Observable stores, built once in AppContainer
│   │   │   ├── GymStore.swift           # the 16 gyms + live busyness, refresh policy
│   │   │   ├── LocationStore.swift      # v1: the single saved location (see note below)
│   │   │   └── MembershipStore.swift    # gyms the user belongs to
│   │   ├── Models/
│   │   │   ├── Gym.swift                # list shape: existing
│   │   │   ├── GymDetail.swift          # detail shape: hours, forecast, links, rates
│   │   │   ├── Busyness.swift           # BusynessLevel enum + Quiet/Moderate/Packed thresholds
│   │   │   ├── Ranking.swift
│   │   │   ├── SavedLocation.swift      # id, name, lat, lng, isDefault — schema stays forward-compatible
│   │   │   └── UserProfile.swift
│   │   ├── Extensions/
│   │   │   ├── Color+Hex.swift          # moved out of Theme.swift
│   │   │   └── URL+AppleMaps.swift
│   │   └── Utilities/
│   │       └── Formatters.swift         # miles, minutes, hours strings
│   │
│   ├── DesignSystem/
│   │   ├── Theme.swift                  # existing color tokens
│   │   ├── Typography.swift
│   │   ├── Spacing.swift
│   │   ├── Components/
│   │   │   ├── BusynessBadge.swift      # word first, percent second
│   │   │   ├── GymLogo.swift            # placeholder until the logo endpoint ships
│   │   │   ├── GlassPill.swift          # frosted map controls
│   │   │   ├── LoadingView.swift        # themed ProgressView wrapper
│   │   │   └── EmptyStateView.swift     # themed ContentUnavailableView wrapper
│   │   └── Styles/
│   │       ├── PrimaryButtonStyle.swift
│   │       └── CardStyle.swift
│   │
│   ├── Features/
│   │   ├── Authentication/
│   │   │   ├── LoginView.swift
│   │   │   ├── SignUpView.swift
│   │   │   └── AuthenticationViewModel.swift    # talks to Core/Auth/AuthService
│   │   │
│   │   ├── AppShell/
│   │   │   ├── AppShellView.swift       # NavigationStack + drawer overlay + current AppRoute
│   │   │   ├── AppShellViewModel.swift  # drawer open/closed, route, sign-out
│   │   │   ├── SideMenuView.swift       # Map / Rankings / Gyms rows
│   │   │   └── ProfileHeaderView.swift  # avatar + name at top of the drawer
│   │   │
│   │   ├── Map/
│   │   │   ├── MapView.swift
│   │   │   ├── MapViewModel.swift       # composes GymStore + LocationStore + MembershipStore
│   │   │   └── Components/
│   │   │       ├── GymAnnotation.swift  # pin, member ring, cluster priority
│   │   │       ├── GymBusynessCard.swift    # zoomed-in card on a pin
│   │   │       ├── MapControlsView.swift
│   │   │       ├── TimeScrubberView.swift
│   │   │       └── BestPickCard.swift
│   │   │                                # no LocationSwitcherView in v1 — one saved location,
│   │   │                                # nothing to switch between; see note below
│   │   │
│   │   ├── Rankings/
│   │   │   ├── RankingsView.swift
│   │   │   ├── RankingsViewModel.swift
│   │   │   ├── RankingsService.swift    # stateless: fetch rankings for (location, time)
│   │   │   └── Components/
│   │   │       └── RankingRow.swift
│   │   │
│   │   ├── Gyms/
│   │   │   ├── GymsView.swift
│   │   │   ├── GymsViewModel.swift      # reads GymStore, writes MembershipStore
│   │   │   └── Components/
│   │   │       ├── GymRow.swift
│   │   │       └── GymSearchBar.swift
│   │   │
│   │   ├── GymDetail/                   # shared push destination from Map and Rankings
│   │   │   ├── GymDetailView.swift
│   │   │   ├── GymDetailViewModel.swift
│   │   │   ├── GymDetailService.swift   # stateless: fetch GymDetail by id
│   │   │   └── Components/
│   │   │       ├── GymHeaderView.swift  # logo + name
│   │   │       ├── ForecastChart.swift
│   │   │       ├── HoursView.swift
│   │   │       └── GymLinksView.swift   # address → Apple Maps, website, waiver
│   │   │
│   │   └── Locations/                   # v1: onboarding only — see note below
│   │       ├── LocationOnboardingView.swift # required, shown once after sign-up, before the app shell
│   │       ├── LocationEditorView.swift     # the create form (name + address/place lookup)
│   │       ├── LocationsViewModel.swift     # creates the one location via LocationStore/API
│   │       └── Components/
│   │           └── LocationSearchField.swift    # MapKit local search field
│   │
│   ├── Previews/
│   │   └── PreviewData.swift            # #if DEBUG sample gyms, rankings, detail, location
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
│
└── BoulderBayTests/
    ├── Core/
    │   ├── Networking/
    │   ├── Auth/
    │   ├── State/
    │   └── Models/
    │       └── GymDecodingTests.swift   # existing
    ├── Features/
    │   ├── Authentication/
    │   ├── AppShell/
    │   ├── Locations/                   # onboarding creates exactly one; store rejects zero
    │   ├── Map/
    │   ├── Rankings/
    │   ├── Gyms/
    │   └── GymDetail/
    └── Support/
        ├── Fixtures/                    # JSON response samples
        ├── Mocks/                       # mock services and stores
        ├── StubURLProtocol.swift        # canned responses for APIClient tests
        └── TestData.swift
```

## Current state

The folders above exist on disk. Only the files that already existed have been
placed; everything else in the tree is still to be written.

**Placed so far:** `App/BoulderBayApp.swift`, `Core/Configuration/AppConfig.swift`,
`Core/Networking/APIClient.swift`, `Core/Networking/APIError.swift` (split out of
`APIClient.swift`), `Core/Networking/APIEnvelope.swift` (split out of `Gym.swift`),
`Core/Models/Gym.swift`, `Core/Extensions/Color+Hex.swift` (extracted from
`Theme.swift`, now internal rather than private), `DesignSystem/Theme.swift`,
`Resources/Assets.xcassets`, and `Core/Models/GymDecodingTests.swift`.

**`App/ContentView.swift`** is the existing connectivity-proof placeholder, moved
here so the build stays green. It is deleted once `RootView` and `AppShellView`
land — it is not part of the target design.

**Empty folders carry a `.gitkeep`,** since git does not track directories.
`project.yml` excludes `**/.gitkeep` from both targets so the placeholders never
reach the app bundle. Delete each one as its folder gains a real file.

**`Info.plist` is generated by XcodeGen** from the `info.properties` block in
`project.yml` and is gitignored — it is not a file to move by hand. Its path is
now `BoulderBay/Resources/Info.plist`, updated in both `project.yml` and
`.gitignore`.

## Auth & location gate (`RootView`)

`RootView` resolves to one of three screens:

1. No session → `LoginView` / `SignUpView` (Authentication feature).
2. Session present, no saved location yet → `LocationOnboardingView`, required,
   shown once. The app shell is not reachable until it completes.
3. Session and a saved location both present → `AppShellView`.

## Locations — v1 scope vs. deferred

**v1 ships one saved location only.** It's created during onboarding and
cannot be added to, edited, or removed from the app. There is no manage
screen, no list, and no location switcher on the Map — with exactly one
location there's nothing to switch between, so `Map/Components/` has no
`LocationSwitcherView`. `LocationStore` and `SavedLocation` still model a
list with an `isDefault` flag rather than a single flat value, so the
backend contract and store shape don't need to change when the next piece
ships.

**Deferred to a future Settings page (v2, not built now):**
- Add up to three saved locations; a Settings entry point that doesn't
  exist yet, since the app has no Settings screen today.
- A location switcher on Map once there's more than one to switch between.
- Delete rules: refuse deletion while only one location remains. When more
  than one exists, deleting the current default falls back to the
  **originally-created location** — not an arbitrary remaining one — as the
  new default.

This section exists so that design isn't lost; none of it should turn into
files or folders until the Settings page is actually being built.

## Design rules

- **Stores own shared state, services stay stateless.** Anything more than
  one screen reads lives in `Core/State/`. A feature service only fetches,
  and only when no store already covers it — Map and Gyms have no service
  of their own because the stores cover them.
- **View models compose, they don't cache.** A view model holds screen-local
  state (selected pin, search text) and reads gyms/location/memberships from
  the stores it's given.
- **Auth is one type.** The session is app-wide: one `AuthService` in
  `Core/Auth/`. Nothing under `Features/Authentication/` talks to
  supabase-swift directly.
- **`GymDetail` is a shared push destination**, reached via `AppRoute` from
  both Map and Rankings — never referenced directly by either feature.
- **Feature folders never import each other.**
