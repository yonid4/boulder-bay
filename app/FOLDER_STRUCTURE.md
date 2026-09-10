# Boulder Bay — iOS App Folder Structure

Target layout for `app/BoulderBay`. The folders are scaffolded; the files are
filled in as screens land — see "Current state" below for what exists today.
See root `CLAUDE.md` for nav structure and `boulder_bay_plan.md` for the
feature spec this implements.

## Tree

```
app/
├── project.yml                          # info.path → Resources/Info.plist; configFiles → Config/App.xcconfig
├── Config/
│   ├── App.xcconfig                     # committed; `#include? "Supabase.xcconfig"`
│   ├── Supabase.example.xcconfig        # committed template (note the `https:/$()/` trick)
│   └── Supabase.xcconfig                # gitignored: BB_SUPABASE_URL / BB_SUPABASE_ANON_KEY
│
├── BoulderBay/
│   ├── App/
│   │   ├── BoulderBayApp.swift          # @main, builds AppContainer.live(), injects it, starts it
│   │   ├── AppContainer.swift           # composition root + launch phase (resolving → ready)
│   │   ├── RootView.swift               # three-way gate — see "Auth & location gate" below
│   │   └── AppRoute.swift               # .map / .rankings / .gyms roots, .gymDetail(slug) push; debug start route
│   │
│   ├── Core/
│   │   ├── Configuration/
│   │   │   └── AppConfig.swift          # apiBaseURL, supabaseURL/AnonKey, useMockAPI
│   │   ├── Networking/
│   │   │   ├── APIClient.swift          # the protocol: one method per planned endpoint
│   │   │   ├── LiveAPIClient.swift      # URLSession transport, bearer token, envelope, status → APIError
│   │   │   ├── AuthenticatedRequest.swift   # APIRequest description → URLRequest
│   │   │   ├── APICoding.swift          # JSONDecoder/Encoder.api (ISO 8601 with/without fractions)
│   │   │   ├── APIEnvelope.swift        # {"data": …}
│   │   │   ├── APIError.swift
│   │   │   ├── Endpoints/               # LiveAPIClient's protocol methods, grouped by route
│   │   │   │   ├── APIClient+Gyms.swift
│   │   │   │   ├── APIClient+Rankings.swift
│   │   │   │   └── APIClient+Me.swift
│   │   │   └── Mock/                    # the in-process backend, on by default in Debug
│   │   │       ├── MockAPIClient.swift  # actor; one account's memberships + locations in memory
│   │   │       ├── SeedGyms.swift       # 16 gyms + 112 hours rows, verbatim from b00fd69a53b6
│   │   │       ├── MockBusyness.swift   # the mockup's curve, clipped to real hours
│   │   │       └── MockRanking.swift    # Haversine, 6 + miles×2.3, the prototype score
│   │   ├── Auth/
│   │   │   ├── AuthService.swift        # protocol + AuthSession (@Observable) + AuthState/AuthUser
│   │   │   ├── AuthServiceError.swift
│   │   │   ├── SupabaseAuthService.swift    # wraps supabase-swift; the only file that imports it
│   │   │   └── MockAuthService.swift    # any email + 6-char password; remembered in UserDefaults
│   │   ├── State/                       # app-wide @Observable stores, built once in AppContainer
│   │   │   ├── GymStore.swift           # the 16 gyms + today's hours + live reading
│   │   │   ├── LocationStore.swift      # list-shaped with a default; refuses to delete the last
│   │   │   ├── MembershipStore.swift    # optimistic toggle, PUTs the whole set
│   │   │   └── RankingStore.swift       # planned hour (scrubber) + scored list; read by Map and Rankings
│   │   ├── Models/                      # Codable, explicit snake_case keys
│   │   │   ├── Gym.swift                # list shape (+ LiveReading)
│   │   │   ├── GymDetail.swift          # list shape + 7 days of hours + today's forecast
│   │   │   ├── GymHours.swift · GymRates.swift · ClockTime.swift · Brand.swift
│   │   │   ├── Busyness.swift           # BusynessLevel thresholds, ForecastPoint, best-window helper
│   │   │   ├── Ranking.swift            # RankingEntry, Rankings
│   │   │   ├── SavedLocation.swift      # + NewSavedLocation (POST body)
│   │   │   └── UserProfile.swift
│   │   ├── Extensions/
│   │   │   ├── Color+Hex.swift
│   │   │   ├── String+Initials.swift    # the monogram rule for logo fallbacks
│   │   │   └── URL+AppleMaps.swift      # MKMapItem from coordinates
│   │   └── Utilities/
│   │       └── Formatters.swift         # BayArea (Pacific calendar) + Format (hours, money, miles)
│   │
│   ├── DesignSystem/
│   │   ├── Theme.swift · Typography.swift · Spacing.swift
│   │   ├── Components/
│   │   │   ├── BusynessBadge.swift      # word first, percent second; + MemberBadge
│   │   │   ├── GymLogoView.swift        # async mark from logo_url, on-dark template, monogram fallback
│   │   │   ├── GlassPill.swift          # + MenuButton, BackButton
│   │   │   ├── ScreenHeader.swift
│   │   │   ├── TimeScrubberView.swift   # + TimeChip (shared by Map and Rankings)
│   │   │   └── StateViews.swift         # LoadingView, EmptyStateView, SearchField, AuthTextFieldStyle
│   │   └── Styles/
│   │       ├── PrimaryButtonStyle.swift # + SecondaryButtonStyle
│   │       ├── PillButtonStyle.swift    # Add / Added / Remove
│   │       └── CardStyle.swift          # .card(), .floatingShadow()
│   │
│   ├── Features/                        # feature folders never import each other
│   │   ├── Authentication/
│   │   │   ├── LoginView.swift          # + AuthFlowView (host), AuthScreen, AppIconTile, ConfirmEmailView
│   │   │   ├── SignUpView.swift
│   │   │   └── AuthenticationViewModel.swift
│   │   ├── AppShell/
│   │   │   ├── AppShellView.swift       # NavigationStack + route switch + drawer overlay
│   │   │   ├── AppShellViewModel.swift  # root, pushed path, menu state; shared via environment
│   │   │   ├── SideMenuView.swift       # + SideMenuOverlay (backdrop, slide, drag-to-close)
│   │   │   └── ProfileHeaderView.swift  # user card + sign-out popover
│   │   ├── Map/
│   │   │   ├── MapView.swift
│   │   │   ├── MapViewModel.swift       # pins joined with rankings; overlap rule; camera; selection
│   │   │   └── Components/
│   │   │       ├── GymAnnotation.swift  # dot, member ring, zoomed-in chip; + LocationDot
│   │   │       ├── GymBusynessCard.swift    # bottom card; + BestPickPill
│   │   │       └── MapControlsView.swift
│   │   ├── Rankings/
│   │   │   ├── RankingsView.swift
│   │   │   ├── RankingsViewModel.swift  # best + 7, why-line, subtitle; reads RankingStore
│   │   │   └── Components/
│   │   │       ├── BestPickCard.swift
│   │   │       └── RankingRow.swift
│   │   ├── Gyms/
│   │   │   ├── GymsView.swift
│   │   │   ├── GymsViewModel.swift      # search by name/city/brand; reads GymStore, writes MembershipStore
│   │   │   └── Components/
│   │   │       └── GymRow.swift         # + GymListCard
│   │   ├── GymDetail/                   # shared push destination from Map, Rankings and Gyms
│   │   │   ├── GymDetailView.swift
│   │   │   ├── GymDetailViewModel.swift # busyness at the scrubbed hour, best window, bars, rows
│   │   │   ├── GymDetailService.swift   # stateless fetch
│   │   │   └── Components/
│   │   │       ├── GymHeaderView.swift · BusynessCard.swift · ForecastChart.swift
│   │   │       ├── InfoRows.swift       # address → Apple Maps, hours, rates
│   │   │       └── GymLinksView.swift   # Website / Sign waiver
│   │   └── Locations/                   # v1: onboarding only — see note below
│   │       ├── LocationOnboardingView.swift
│   │       ├── LocationEditorView.swift
│   │       ├── LocationsViewModel.swift
│   │       └── Components/
│   │           └── LocationSearchField.swift    # + PlaceSearch (MKLocalSearchCompleter)
│   │
│   ├── Previews/
│   │   └── PreviewData.swift            # #if DEBUG: seed-built gyms frozen at 5 PM, AppContainer.preview()
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist                   # generated by XcodeGen, gitignored
│
└── BoulderBayTests/
    ├── Core/
    │   ├── Auth/MockAuthServiceTests.swift
    │   ├── Models/                      # PayloadDecodingTests, BusynessTests, InitialsTests
    │   ├── Networking/                  # LiveAPIClientTests (stub URLProtocol), MockAPIClientTests
    │   └── State/StoreTests.swift       # all four stores, Format, cancellation
    ├── Features/                        # one view-model test file per feature, AppContainerTests
    └── Support/
        ├── Fixtures/                    # one JSON sample per endpoint, envelope included
        ├── Mocks/SpyAPIClient.swift     # records calls, can fail the next one
        ├── StubURLProtocol.swift
        └── TestData.swift               # Fixture loader
```

## Current state

Every screen in the mockup is built and the placeholder root view is gone. The
tree above is what is on disk. Two departures from the first draft of this
document, both for the doc's own rule that shared state lives in a store:

- **`RankingStore` replaced the planned `RankingsService`.** Map pins take
  busyness and travel time from the same scored list Rankings displays, so it
  is a store. It also owns the scrubber's planned hour and the debounced refetch.
- **`TimeChip` / `TimeScrubberView` live in `DesignSystem/Components`,** not
  under `Map/`, because Rankings uses them too.

## Mock mode and configuration

- **Data.** Debug builds run on `MockAPIClient` (`BB_USE_MOCK_API`, overridable
  per run with the `-BBUseMockAPI NO` launch argument). It serves the sixteen
  seed gyms with synthesized busyness and keeps one account in memory: signing
  **in** seeds Home (Redwood City) plus the four Movement memberships; signing
  **up** starts empty so onboarding runs. Release builds always use `LiveAPIClient`.
- **Auth.** `SupabaseAuthService` when `Config/Supabase.xcconfig` has both
  values, `MockAuthService` otherwise (fresh clone, CI). The two are independent:
  real Supabase sign-in with mock data is the usual dev setup today.
- **Logos.** Nothing serves `gym_logos` yet, so the mock sends `logo_url: null`
  and `GymLogoView` shows the monogram. The component already fetches from the
  URL and renders a light-tinted template on the green best-pick card.
- **Debug launch arguments** (`AppRoute.debugStartRoute`):
  `-BBStartRoute map|rankings|gyms|detail:<slug>` and `-BBStartMenuOpen YES`.

**Empty folders carry a `.gitkeep`;** `project.yml` excludes `**/.gitkeep` from
both targets. Delete each one as its folder gains a real file.

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
  and only when no store already covers it — `GymDetailService` is the one
  service, because only the detail screen reads a `GymDetail`.
- **View models compose, they don't cache.** A view model holds screen-local
  state (selected pin, search text) and reads gyms/location/memberships from
  the stores it's given.
- **Auth is one type.** The session is app-wide: one `AuthService` in
  `Core/Auth/`. Nothing under `Features/Authentication/` talks to
  supabase-swift directly.
- **`GymDetail` is a shared push destination**, reached via
  `AppShellViewModel.openDetail(slug:)` from Map, Rankings and Gyms — never
  referenced directly by any of them.
- **Screens create their view model inside one `.task`** that also loads it.
  A `.task(id:)` keyed on the model's presence cancels the load it just
  started; that bug has been paid for once.
- **Feature folders never import each other.**
