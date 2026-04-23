# PetBnB Architecture Overview

*Snapshot as of 2026-04-24 — end of Phase 2d. See `docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md` for the original design spec and `docs/superpowers/plans/*.md` for per-phase plans.*

---

## System at a glance

Three client surfaces sit on top of a single Supabase project. Two external services (iPay88 for payments, APNs for pushes) integrate via Supabase Edge Functions.

```
┌──────────────────────────────┐  ┌──────────────────────────────┐  ┌──────────────────────────────┐
│  Owner iOS app               │  │  Business web dashboard      │  │  Public web (Phase 5)        │
│  PetBnB/ios/                 │  │  PetBnB/web/                 │  │  Same Next.js codebase       │
│  SwiftUI · iOS 17+           │  │  Next.js 16 · App Router     │  │  (SSR · anon-readable RLS)   │
│  Supabase Swift 2.44 SDK     │  │  @supabase/ssr               │  │  Deferred — not started      │
│                              │  │                              │  │                              │
│  Tabs:                       │  │  Routes:                     │  │                              │
│   • Discover                 │  │   • Inbox (KPIs + requests)  │  │                              │
│   • Bookings (Realtime)      │  │   • Calendar (14-day grid)   │  │                              │
│   • Pets                     │  │   • Listing (photos/kennels) │  │                              │
│                              │  │   • Reviews (stub)           │  │                              │
│  XCTest: 14 tests            │  │   • Payouts (stub)           │  │                              │
│                              │  │   • Settings → KYC           │  │                              │
│                              │  │  Playwright: 4 E2E           │  │                              │
└──────────────┬───────────────┘  └──────────────┬───────────────┘  └──────────────┬───────────────┘
               │                                  │                                  │
               │  RPCs · Storage · Auth           │  RPCs · Storage · Auth           │  (anon RLS,
               │  RealtimeV2                      │                                  │   future)
               └─────────────────┬────────────────┴──────────────────┬───────────────┘
                                 │                                   │
┌────────────────────────────────┴───────────────────────────────────┴───────────────────────────────┐
│                                                                                                     │
│   SUPABASE (single project · live at github.com/fabiatan/petbnb)                                    │
│                                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│   │  PostgreSQL 17                                                                              │   │
│   │                                                                                             │   │
│   │  20 migrations (000_bootstrap_extensions → 019_fix_confirm_payment_jwt_check)               │   │
│   │                                                                                             │   │
│   │  15 tables + RLS on every one + 23 policies                                                 │   │
│   │  9 enum types                                                                               │   │
│   │  9 state-machine SQL functions (SECURITY DEFINER)                                           │   │
│   │  2 membership helpers (is_business_member, is_pet_owner — SECURITY DEFINER)                 │   │
│   │  4 pg_cron sweep functions                                                                  │   │
│   │                                                                                             │   │
│   │  Tests: 79 pgTAP assertions across 14 files                                                 │   │
│   └─────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                     │
│   ┌───────────────────────────┐  ┌───────────────────────────┐  ┌───────────────────────────┐       │
│   │  Storage (3 buckets)      │  │  Auth                     │  │  Realtime                 │       │
│   │  • kyc-documents (priv)   │  │  Email + password         │  │  Postgres changes         │       │
│   │  • listing-photos (pub)   │  │  Keychain (iOS)           │  │  filtered by owner_id     │       │
│   │  • pet-vaccinations (priv)│  │  Session cookies (web)    │  │  (iOS MyBookings tab)     │       │
│   └───────────────────────────┘  └───────────────────────────┘  └───────────────────────────┘       │
│                                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│   │  Edge Functions (Deno)                                                                      │   │
│   │  • ipay88-webhook/                                                                          │   │
│   │    receives iPay88 POST → verifier.verify() → confirm_payment() RPC (service_role)          │   │
│   │    MockVerifier (dev) + Ipay88Verifier stub (prod, sandbox creds pending)                   │   │
│   │    Tests: 5 Deno unit tests                                                                 │   │
│   └─────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                     │
└────────────┬──────────────────────────────────────────────────────────────────────┬─────────────────┘
             │                                                                      │
             ▼                                                                      ▼
   ┌──────────────────────┐                                           ┌──────────────────────┐
   │  iPay88              │                                           │  APNs (Phase 2e)     │
   │  FPX + card (MYR)    │                                           │  Push notifications  │
   │  Sandbox creds TBD   │                                           │  Deferred            │
   │  POSTs to webhook    │                                           │                      │
   └──────────────────────┘                                           └──────────────────────┘
```

---

## Data model — 15 tables, grouped by concern

### Identity (3)

| Table | Purpose | Key constraints |
|---|---|---|
| `user_profiles` | Extends `auth.users` with app fields | `id → auth.users.id`; `primary_role ∈ {owner, business_admin, platform_admin}` |
| `pets` | Owned by a user profile | `owner_id → user_profiles`, cascade delete; `species ∈ {dog, cat}` |
| `vaccination_certs` | File reference + expiry per pet | `pet_id → pets`, cascade delete; `expires_on > issued_on` CHECK |

### Businesses & listings (4)

| Table | Purpose | Key constraints |
|---|---|---|
| `businesses` | Commercial boarding business | unique `slug`; `kyc_status ∈ {pending, verified, rejected}`; `commission_rate_bps ∈ [0, 10000]` |
| `business_members` | Join users to businesses | PK `(business_id, user_id)`; MVP `role = 'admin'` |
| `listings` | One per business in MVP | unique `business_id`; `cancellation_policy ∈ {flexible, moderate, strict}` |
| `kennel_types` | Bookable variants inside a listing | `species_accepted ∈ {dog, cat, both}`; `size_range ∈ {small, medium, large}`; `capacity > 0`; `peak_price ≥ base_price` enforced in validator |

### Availability (2)

| Table | Purpose |
|---|---|
| `peak_calendar` | Platform-wide peak dates (MY public holidays + school holidays) + per-business overrides |
| `availability_overrides` | Manual per-day blocks by a business on a specific kennel type |

### Bookings (3)

| Table | Purpose | Key constraints |
|---|---|---|
| `bookings` | Booking row + locked commission + state | 9-value `status` enum; `check_out > check_in` + `nights = check_out - check_in` CHECK; unique `ipay88_reference`; `is_instant_book` column used by sweeps |
| `booking_pets` | Many-to-many (booking × pet) | PK `(booking_id, pet_id)` |
| `booking_cert_snapshots` | Frozen cert references at request time | `vaccination_cert_id → vaccination_certs` |

### Post-stay & ops (3)

| Table | Purpose |
|---|---|
| `reviews` | Two-dimension rating: `service_rating` + `response_rating` (both 1–5); 1:1 with completed bookings |
| `review_responses` | Business's public reply to a review |
| `notifications` | In-app feed; 9-value `kind` enum; `user_id` scoped |

---

## State machine — booking transitions

All transitions are `SECURITY DEFINER` SQL functions (see `010_state_transitions.sql`). RLS allows only SELECT on `bookings`; no direct INSERT/UPDATE from any client.

```
(request-to-book path)
 requested ──accept──▶ accepted ──pay(webhook)──▶ confirmed ──check_out──▶ completed
     │                    │
     │                    └─24h no payment──▶ expired
     ├─decline──▶ declined
     └─24h no action──▶ expired

(instant-book path)
 pending_payment ──pay(webhook)──▶ confirmed ──check_out──▶ completed
       └─15min no payment──▶ expired

(from confirmed)
 confirmed ──owner cancels──▶ cancelled_by_owner    (refund per listing policy)
 confirmed ──business cancels──▶ cancelled_by_business  (full refund + penalty flag)
```

### Functions that drive it

| Function | Caller | Source file |
|---|---|---|
| `create_booking_request` | Owner (iOS) | `010_state_transitions.sql` |
| `create_instant_booking` | Owner (iOS) | `010_state_transitions.sql` |
| `accept_booking` | Business admin (web) | `010_state_transitions.sql` — Phase 2c bugfix added re-check |
| `decline_booking` | Business admin (web) | `010_state_transitions.sql` |
| `create_payment_intent` | Owner (iOS) | `010_state_transitions.sql` |
| `confirm_payment` | **Service role only** (Edge Function) | `010_state_transitions.sql` + `019_fix_confirm_payment_jwt_check.sql` |
| `cancel_booking_by_owner` | Owner (iOS) | `010_state_transitions.sql` |
| `cancel_booking_by_business` | Business admin (web) | `010_state_transitions.sql` |
| `create_business_onboarding` | Any authenticated user (web) | `013_business_onboarding.sql` |

### Scheduled sweeps (pg_cron)

| Job | Schedule (UTC) | Purpose |
|---|---|---|
| `petbnb_expire_requests` | `*/5 * * * *` | `requested` > 24h → `expired` |
| `petbnb_expire_payments` | `*/5 * * * *` | `accepted` / `pending_payment` past payment_deadline → `expired` |
| `petbnb_complete_past` | `5 16 * * *` (00:05 MY) | `confirmed` + `check_out < today` → `completed`; send review_prompt |
| `petbnb_reconcile_payments` | `*/30 * * * *` | Stub — Phase 3 calls iPay88 lookup API |

---

## RLS / RBAC summary

| Role | Reads | Writes |
|---|---|---|
| **Anon** | Verified+active businesses/listings/kennels (public discovery); `listing-photos` bucket (public read) | Nothing |
| **Owner** (authenticated) | Own profile/pets/certs/bookings/notifications; public businesses; own `pet-vaccinations` files; public `listing-photos` | Own profile/pets/certs; own reviews on `completed` bookings; all bookings writes go through `SECURITY DEFINER` RPCs |
| **Business admin** | Own business/listing/kennels/bookings/reviews; customers' pets + profiles (scoped via `booking_pets` join, Phase 1d); own `kyc-documents`; public + own `listing-photos`; peak_calendar platform + own | Own listing/kennels/photos/amenities/peak; review responses; business creation only via `create_business_onboarding` RPC (no direct INSERT) |
| **Service role** | Everything (used by Edge Function) | Everything — `confirm_payment` guarded to this role only |
| **Platform admin** | Everything via Supabase Studio (no in-app admin UI yet) | Manual KYC approval, commission rate overrides, edge-case refunds |

---

## Happy-path sequence: one full booking, end-to-end

```
Pet owner (iOS)                       Supabase                               Business (web)
─────────────────                     ─────────                              ─────────────
1. Discover + Search
   ──► listings, kennel_types select (public RLS)
                                      returns verified+active rows

2. Tap Continue → Review Screen
   ──► rpc: create_booking_request
       or create_instant_booking
                                      SQL function:
                                        FOR UPDATE on kennel_types
                                        validate cert + availability
                                        compute platform_fee (locked)
                                        INSERT bookings
                                        INSERT booking_pets
                                        INSERT booking_cert_snapshots
                                        INSERT notifications (both sides)
                                      status := requested OR pending_payment

                                      ═════ Realtime channel: bookings ═════▶
                                                                              ◄── business inbox updates

3. MyBookings (Realtime listens)
   ◄── Realtime UPDATE event          ←── business taps Accept (web)
                                      rpc: accept_booking
                                        re-check availability
                                        set payment_deadline = now()+24h

4. Tap "Pay now"
   ──► rpc: create_payment_intent
                                      ipay88_reference := generated
   ◄── ref string
   ──► present iPay88 form (Phase 3 will open in-app webview)

5. User completes payment via iPay88
                                      ╔═══════════════════════╗
                                      ║ iPay88                ║
                                      ║ POST webhook ─────────────► ipay88-webhook Edge Function
                                      ╚═══════════════════════╝    verifier.verify(body)
                                                                   rpc: confirm_payment(ref, amount)
                                                                     │ service_role
                                                                     ▼
                                                                   status := confirmed
                                                                   notifications (both sides)
                                                                   ── returns "RECEIVEOK"

6. MyBookings
   ◄── Realtime UPDATE event          status=confirmed              ◄── business inbox updates

7. Check-out date passes
                                      pg_cron sweep daily 00:05 MY
                                        sweep_complete_past_bookings
                                        status := completed
                                        INSERT review_prompt notification

8. Review prompt (Phase 4 wiring)
```

---

## Test coverage footprint

| Layer | Framework | Count | Command |
|---|---|---|---|
| Postgres / RLS / state machine | pgTAP | 79 assertions, 14 files | `supabase test db` (from project root) |
| Web dashboard E2E | Playwright (Chromium) | 4 tests | `cd web && pnpm exec playwright test` |
| iOS unit tests | XCTest | 14 tests | `cd ios && xcodebuild test ... name=iPhone 17` |
| Edge Function | Deno std | 5 tests | `deno test supabase/functions/ipay88-webhook/` |
| Phase 0 end-to-end | bash + psql | 1 script | `./supabase/scripts/verify-phase0.sh` |

---

## Directory layout

```
PetBnB/
├── README.md                                     Project README (status per phase)
├── supabase/
│   ├── config.toml                               Supabase local config
│   ├── seed.sql                                  Dev seed (2 businesses, 2 owners, 4 kennels)
│   ├── migrations/                               20 files, numbered 000–019
│   ├── tests/                                    14 pgTAP files (79 assertions)
│   ├── scripts/verify-phase0.sh                  End-to-end smoke
│   └── functions/
│       └── ipay88-webhook/
│           ├── index.ts                          Deno handler
│           ├── verifier.ts                       Verifier interface + MockVerifier + Ipay88Verifier stub
│           └── index_test.ts                     Deno tests (5)
├── web/                                          Next.js 16 App Router + Tailwind + shadcn/ui
│   ├── app/
│   │   ├── (auth)/                               sign-in · sign-up · auth server actions
│   │   ├── auth/callback/                        magic-link/OAuth callback
│   │   ├── onboarding/                           business onboarding form + RPC call
│   │   └── dashboard/                            auth-guarded shell (sidebar + KYC banner)
│   │       ├── inbox/                            real pending requests + KPI strip
│   │       ├── calendar/                         14-day availability grid
│   │       ├── listing/                          info editor + photo gallery + kennel CRUD
│   │       ├── reviews/ payouts/                 stubs
│   │       └── settings/kyc/                     4-doc KYC upload
│   ├── components/                               UI components including shadcn primitives
│   ├── lib/
│   │   ├── db/schema.ts                          Drizzle types (hand-written to match Supabase)
│   │   ├── supabase/                             client · server · middleware factories
│   │   └── ...
│   ├── e2e/                                      Playwright specs (onboarding · kyc-upload · listing-editor · accept-booking)
│   └── proxy.ts                                  Next.js 16 middleware (renamed from middleware.ts)
└── ios/                                          SwiftUI iOS 17+ · generated via xcodegen
    ├── project.yml                               xcodegen config
    ├── Config/Shared.xcconfig                    env defaults (Shared.local.xcconfig gitignored)
    ├── Sources/
    │   ├── PetBnBApp.swift                       @main
    │   ├── App/
    │   │   ├── AppState.swift                    Observable root — services injected here
    │   │   └── RootView.swift                    auth gate + TabView
    │   ├── Supabase/                             client provider + env loader
    │   ├── Auth/                                 AuthService + sign-in/sign-up views
    │   ├── Pets/                                 Pet model + service + list/add/detail views + cert upload
    │   ├── Listings/                             Listing + search + detail views + ListingRepository
    │   └── Bookings/                             Booking model + service + review/list/detail/payment-stub + Realtime service
    └── Tests/                                    XCTest (5 files, 14 tests)

docs/superpowers/                                 (in Primary root, not PetBnB/)
├── specs/2026-04-22-petbnb-owner-sitter-booking-design.md
└── plans/
    ├── 2026-04-22-petbnb-phase0-schema-and-state-machine.md
    ├── 2026-04-22-petbnb-phase1a-web-scaffold-and-auth.md
    ├── 2026-04-22-petbnb-phase1b-kyc-upload.md
    ├── 2026-04-22-petbnb-phase1c-listing-editor.md
    ├── 2026-04-23-petbnb-phase1d-inbox-and-calendar.md
    ├── 2026-04-23-petbnb-phase2a-ios-scaffold-auth-pets.md
    ├── 2026-04-23-petbnb-phase2b-ios-discover-browse.md
    ├── 2026-04-23-petbnb-phase2c-ios-booking-and-payments.md
    └── 2026-04-24-petbnb-phase2d-ipay88-webhook-realtime.md
```

---

## Tech stack at a glance

| Layer | Tech | Version |
|---|---|---|
| Database | PostgreSQL | 17 (Supabase CLI 2.90 default) |
| Schema migration | Supabase CLI (SQL files) | 2.90 |
| Schema test | pgTAP | bundled |
| Auth | Supabase Auth (email+password) | — |
| Storage | Supabase Storage | — |
| Realtime | Supabase Realtime v2 | — |
| Scheduled jobs | pg_cron | — |
| Server runtime (Edge) | Deno | 2.x |
| Web framework | Next.js (App Router) | 16 |
| Web UI | Tailwind CSS v4 + shadcn/ui (base-ui) | — |
| Web DB ORM (types only) | Drizzle ORM | — |
| Web E2E | Playwright (Chromium) | 1.59 |
| iOS framework | SwiftUI | iOS 17+ |
| iOS project gen | xcodegen | 2.39+ |
| iOS Supabase SDK | supabase-swift | 2.44 |
| iOS unit test | XCTest | — |

---

## Deferred scope (by phase)

| Phase | What | Why deferred |
|---|---|---|
| 2e | Apple Push Notifications (APNs) | Needs one-time .p8 key + bundle ID entitlements + device testing |
| 3 | Real iPay88 HMAC verifier; webhook audit log; retry policies | Waiting on iPay88 sandbox creds; audit log is prod-hardening |
| 4 | Reviews wiring end-to-end (owner rates after checkout; business responds) | No functional urgency before Phase 6 beta |
| 5 | Public SEO pages; transactional email (Resend); email receipts | Phase 5 is public-launch polish |
| 6 | Closed beta in KL (5 seeded businesses, 20 E2E bookings) | Requires all prior phases green + real iPay88 |

---

## Known gotchas (baked into memory for future sessions)

1. **Next.js 16**: `middleware.ts` is now `proxy.ts` at web root. `lib/supabase/middleware.ts` helper keeps its name (not a framework file convention).
2. **Next.js 16 `revalidatePath`** alone doesn't update the current page's server component from a server-action response. Client components invoking mutations also need `router.refresh()` from `next/navigation`. Listing page + dashboard components use `export const dynamic = "force-dynamic"` where needed.
3. **Supabase CLI 2.90**: "anon key" is now "Publishable key" (`sb_publishable_*` format). Works identically.
4. **PostgREST 14 JWT claims**: uses `request.jwt.claims` (full JSON blob) not `request.jwt.claim.role`. Phase 0 `confirm_payment`'s service-role guard was patched via `019_fix_confirm_payment_jwt_check.sql` with a `COALESCE` across both formats for backward compat.
5. **shadcn Dialog** now uses `@base-ui/react` (Radix successor). Trigger uses `render={element}` prop, not Radix's `asChild`.
6. **iOS 26 SDK** changed `"\(value, specifier: "%.0f")"` interpolation label. Prefer `String(format: "%.0f", value)` for numeric formatting.
7. **Supabase Swift 2.44 Realtime**: `import Supabase` re-exports Realtime (no separate `import Realtime` needed). `RealtimeChannelV2`, `AnyAction`, `postgresChange(.self, schema:table:filter:)` return AsyncStream. `await channel.subscribeWithError()` to start; `await channel.unsubscribe()` is async but NOT throws — no `try?`.
8. **xcconfig URL trick**: use `http:/$()/127.0.0.1:54321` to preserve `//` through xcconfig's comment parser.
9. **`xcconfig #include?`** must come AFTER defaults so local overrides win (Phase 2a gotcha).
10. **`SUPABASE_URL` / `SUPABASE_ANON_KEY`** are injected into `Info.plist` via `project.yml` `info.properties`, then read at runtime via `Bundle.main.object(forInfoDictionaryKey:)`.
11. **SourceKit-LSP false positives** in the Claude Code editor for iOS files ("No such module 'Supabase'", "Cannot find X in scope"). Don't reflect real build state — always trust `xcodebuild` / `xcodebuild test`.

---

## How to run everything locally

```bash
# From PetBnB/ project root

# 1. Backend
supabase start                                  # boots Postgres + Storage + Auth + Studio + Realtime
supabase db reset                               # applies migrations + seed
supabase test db                                # 79 pgTAP assertions
./supabase/scripts/verify-phase0.sh             # end-to-end Phase 0 acceptance

# 2. Edge function (iPay88 webhook)
supabase functions serve ipay88-webhook --no-verify-jwt

# 3. Web dashboard
cd web
cp .env.local.example .env.local                # then paste Publishable key from `supabase status`
pnpm install
pnpm dev                                        # http://localhost:3000
pnpm exec playwright test                       # 4 E2E tests

# 4. iOS app
cd ios
cp Config/Shared.local.xcconfig.example Config/Shared.local.xcconfig
# paste Publishable key into Config/Shared.local.xcconfig
xcodegen generate
open PetBnB.xcodeproj
# Cmd-R in Xcode on an iOS 17+ simulator
xcodebuild test -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=         # 14 XCTest tests
```
