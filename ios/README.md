# PetBnB iOS (Phase 2a)

Owner-facing SwiftUI app. Backed by the Supabase project at `../supabase`.

## Setup

1. `brew install xcodegen` (if not already installed).
2. From `../`, start Supabase: `supabase start`.
3. Copy the xcconfig template and paste the Publishable key from `supabase status`:
   ```bash
   cp Config/Shared.local.xcconfig.example Config/Shared.local.xcconfig
   # edit Shared.local.xcconfig — paste Publishable key
   ```
4. Generate the Xcode project:
   ```bash
   xcodegen generate
   open PetBnB.xcodeproj
   ```
5. In Xcode: select an iOS 17+ simulator, Cmd-R to run.

## CLI

```bash
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'generic/platform=iOS Simulator'
xcodebuild test  -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Layout

```
Sources/
  PetBnBApp.swift             @main entry
  App/
    AppState.swift            Observable root state
    RootView.swift            auth-gated router
  Auth/
    AuthService.swift
    SignInView.swift
    SignUpView.swift
  Pets/
    Pet.swift                 Codable model
    VaccinationCert.swift
    PetService.swift
    PetListView.swift
    AddPetView.swift
    PetDetailView.swift
  Supabase/
    SupabaseEnv.swift
    SupabaseClientProvider.swift
  Info.plist                  xcconfig values injected at build
Tests/
  PetBnBTests.swift
  AuthServiceTests.swift
  PetServiceTests.swift
Config/
  Shared.xcconfig             defaults (tracked)
  Shared.local.xcconfig       real values (gitignored)
```

## Handoff to Phase 2b

- TabView with Discover + Bookings + Profile goes into `RootView.swift` when there are enough surfaces.
- Listing browse + detail pages read from the public `listings` + `kennel_types` tables — RLS already allows anon read for verified/active businesses.
- Phase 2b will introduce `ListingService` + `ListingRepository` alongside the existing `PetService`.

## Phase 2a limitations

- No photo thumbnail for pets yet (avatar_url is in the schema but UI is text-only in 2a).
- Cert expiry date defaults to "today + 1 year" on upload; user picks the real expiry later (2b or later slice).
- No edit or delete for pets in 2a; only create + read.
- Sign-out button is in the Pet list toolbar for dev convenience; proper Settings screen comes in 2b or 2c.
- Works only against local Supabase (`http://127.0.0.1:54321`) out of the box. The xcconfig also allows pointing at a hosted instance by changing `SUPABASE_URL` + `SUPABASE_ANON_KEY`.

## Phase 2b — Discover + browse

1. `RootView` now wraps the authenticated app in a `TabView` with Discover + Pets tabs.
2. `DiscoverView` collects a `SearchCriteria` (city, check-in, check-out, selected pet) and pushes to `SearchResultsView`.
3. `SearchResultsView` calls `ListingRepository.search(criteria:)` — case-insensitive city match, filtered to `kyc_status='verified' AND status='active'` via existing Phase 0 RLS.
4. Tapping a result pushes to `ListingDetailView` which calls `ListingRepository.detail(businessId:)` to fetch the business + listing + active kennels.
5. `ListingDetailView` has a photo carousel (built from `listing-photos` public bucket URLs) and a kennel picker. Tapping Continue navigates to `BookingPlaceholderView` — the real booking flow lands here in Phase 2c.
6. Availability-aware filtering isn't done yet. The search returns any verified/active business in the city; Phase 2c runs the real availability check at booking-intent creation.

## Known Phase 2b limitations

- No ratings / review counts — still shows placeholder; wires up in Phase 4.
- No favorites/wishlist.
- No map view or distance-to-user.
- No availability filter on search (Phase 2c).
- Photo carousel has no full-screen zoom.
- `BookingPlaceholderView` uses synthetic dates (today+7 → today+12) because the Phase 2b nav doesn't thread the real `SearchCriteria` through to the detail screen. Phase 2c plumbs it properly when the real booking-request screen takes over.
