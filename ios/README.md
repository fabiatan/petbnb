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

## Phase 2c — Booking flow + payment stub

1. Tapping Continue on `ListingDetailView` now pushes `BookingReviewView`, which shows the booking summary (business, kennel, dates, pet, price) and a Send-request / Book-now button (depending on `kennel.instant_book`).
2. Submitting calls `BookingService.createBooking` which routes to Phase 0's `create_booking_request` or `create_instant_booking` RPC and returns the new booking id.
3. The app pushes `MyBookingsView` which reloads on pull-down. Bookings are grouped by status: Pay now / Awaiting response / Upcoming / Completed / Other.
4. `BookingDetailView` drills into a single booking. If status is `accepted` or `pending_payment`, a Pay-now button opens `PaymentStubView`. If status is `confirmed`, a Cancel button calls `cancel_booking_by_owner`.
5. `PaymentStubView` calls `create_payment_intent` to get the `ipay88_reference`, then shows a DEV psql snippet to simulate the webhook:
   ```
   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
     -c "SELECT confirm_payment('<ref>', <amount>::numeric);"
   ```
   Running this flips the booking to `confirmed`. Tap Refresh status to see the updated state.

## Phase 2c known limitations

- Payment completion is manual (via psql). Phase 2d wires real iPay88 + webhook handling.
- No realtime status push — pull-to-refresh.
- No cancellation refund computation.
- Cert expiry isn't preflight-checked on the client; the server RPC will reject a booking if the cert doesn't cover the stay. The error message surfaces in BookingReviewView's red text.
- One pet per booking on the iOS side (the backend supports multiple; UI can add multi-select later).

## Phase 2d — iPay88 webhook + Realtime

1. `supabase/functions/ipay88-webhook/` receives iPay88's payment POST and calls `confirm_payment`. Ships with a MockVerifier; real HMAC plugs into `Ipay88Verifier` when sandbox creds arrive.
2. Run locally:
   ```bash
   supabase functions serve ipay88-webhook --no-verify-jwt
   ```
3. `BookingRealtimeService` subscribes iOS to `public.bookings` filtered by `owner_id=eq.<caller>` using Supabase Swift's RealtimeV2 API. MyBookingsView starts the subscription on appear, stops on disappear.

## Phase 2d known limitations

- iPay88 HMAC verification is stubbed (`Ipay88Verifier` throws). Swap in real implementation when sandbox creds arrive — see comments in `verifier.ts`.
- No automatic retry on webhook delivery failure — Phase 5+.
- APNs push notifications are NOT in Phase 2d (deferred to Phase 2e).
- Realtime reconnects automatically on network change, but if the user's JWT expires mid-session the subscription silently drops. Phase 5 polish.
