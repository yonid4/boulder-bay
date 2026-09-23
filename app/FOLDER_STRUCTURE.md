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
│   │   │   ├── LocationStore.swift      # saved-location list; current UI creates one (see below)
│   │   │   └── MembershipStore.swift    # gyms the user belongs to
│   │   ├── Models/
│   │   │   ├── LocalDate.swift          # validated yyyy-MM-dd calendar value
│   │   │   ├── LocalTime.swift          # validated HH:mm:ss wall-clock value
│   │   │   ├── Gym.swift                # gym summary and brand
│   │   │   ├── GymDetail.swift          # detail shape: hours, forecast, links, rates
│   │   │   ├── Busyness.swift           # resolved busyness and forecast shapes
│   │   │   ├── Ranking.swift
│   │   │   ├── SavedLocation.swift
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
│   │   │   ├── AuthenticationView.swift         # one screen, sign-in / sign-up toggle (per the mockup)
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
│   │   │                                # no LocationSwitcherView in the current UI phase;
│   │   │                                # multi-location UI is a separate task (see below)
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

The folders above exist on disk. Files not listed below are still to be written.

**Placed so far:** `App/BoulderBayApp.swift`, `App/AppContainer.swift`,
`Core/Auth/AuthService.swift`, `Core/Configuration/AppConfig.swift`,
`Core/Networking/APIClient.swift`, `Core/Networking/APIError.swift` (split out of
`APIClient.swift`), `Core/Networking/APIEnvelope.swift` (split out of `Gym.swift`),
the complete response-model layer under `Core/Models/`, `Core/Extensions/Color+Hex.swift`
(extracted from `Theme.swift`, now internal rather than private),
`DesignSystem/Theme.swift`, `DesignSystem/Styles/PrimaryButtonStyle.swift`,
`Resources/Assets.xcassets`, `App/RootView.swift`, the Map feature (`MapView.swift`,
`MapViewModel.swift`, `GymPinView.swift`, `SelectedGymCard.swift` — flat for now rather than
under `Components/`; the hour slider is inline in `MapView` until `TimeScrubberView` is
split out), and the Authentication feature (`AuthenticationView.swift` +
`AuthenticationViewModel.swift`). Model contract tests live under
`BoulderBayTests/Core/Models/`; the view-model tests under
`BoulderBayTests/Features/Authentication/` build a real `AuthService` over
`Support/StubURLProtocol.swift` and `Support/Mocks/InMemoryAuthStorage.swift`.

**`RootView` is a two-way gate for now** — auth screen without a session, `MapView`
with one. Location onboarding and `AppShellView` slot in once they exist (see below).
The old `App/ContentView.swift` connectivity placeholder is gone.

**Empty folders carry a `.gitkeep`,** since git does not track directories.
`project.yml` excludes `**/.gitkeep` from both targets so the placeholders never
reach the app bundle. Delete each one as its folder gains a real file.

**`Info.plist` is generated by XcodeGen** from the `info.properties` block in
`project.yml` and is gitignored — it is not a file to move by hand. Its path is
now `BoulderBay/Resources/Info.plist`, updated in both `project.yml` and
`.gitignore`.

## Auth & location gate (`RootView`)

`RootView` resolves to one of three screens:

1. No session → `AuthenticationView` (Authentication feature).
2. Session present, no saved location yet → `LocationOnboardingView`, required,
   shown once. The app shell is not reachable until it completes.
3. Session and a saved location both present → `AppShellView`.

## Locations — API contract vs. current UI

The backend contract supports **one to three saved locations** with list, create, read, update
and delete operations. It always keeps one default: the first location becomes default, promoting
another is atomic, the last location cannot be deleted, and deleting the default promotes the
oldest remaining location. Rankings return a separate ordered list for every saved location so a
future switch is entirely local after one fetch.

The current iOS implementation phase still creates only the first location during required
onboarding. Add/edit/delete controls and `LocationSwitcherView` are a separate UI task, so the
tree above does not add them yet. That later design must preserve the existing Map / Rankings /
Gyms navigation; no Settings route is implied or approved by the backend capability.

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
