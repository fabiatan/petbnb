# PetBnB — Owner + Sitter Booking (MVP) — Design

**Date:** 2026-04-22
**Author:** Fabian (Lumarion Technologies)
**Status:** Draft — pending user approval
**Scope slice:** First of at least three slices for the PetBnB superapp. See "Deferred scope" for what comes later.

---

## 1. Summary

PetBnB is a two-sided marketplace iOS app (plus a web surface) connecting Malaysian pet owners with commercial pet boarding businesses. Owners discover, book, pay, and rate; businesses onboard, list kennel types, accept requests, and get paid.

This spec covers **only the owner + sitter booking path**. Pet clinics, disputes, messaging, individual (non-business) sitters, and adjacent services are explicitly deferred.

**The product is Airbnb/Booking.com-shaped**, not SaaS-shaped. The platform takes a commission per confirmed booking and provides discovery + trust infrastructure; it does not sell boarding-management software to individual businesses.

## 2. Product decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| D1 | Sitters are commercial boarding businesses only. No individual/non-business sitters in MVP. | You said "register their company." Individual-host model requires trust+safety infrastructure (background checks, insurance) that would delay shipping by months. |
| D2 | Marketplace shape (consumer-facing, commission-based), not SaaS-shape. | "Superapp for pet owners" only makes sense with a discovery layer. SaaS-for-businesses is a separate (deferred) lane. |
| D3 | iOS app for owners + Next.js web dashboard for businesses + public SEO web pages. Shared Supabase backend. | Each user type gets the right tool. SEO matters for a marketplace. |
| D4 | Malaysia-first (KL/Selangor/Penang seed cities), MYR, iPay88 for payments. | Matches Lumarion's home market and reuses Court Booking POC's iPay88 integration. |
| D5 | One listing per business. Inside: kennel-type variants (Small Dog Suite / Large Dog Suite / Cat Room, etc.). | Matches Booking.com mental model: one hotel, many room types. |
| D6 | Pricing is per-night per-kennel with peak/off-peak. Each night independently priced based on its calendar status; total = sum of nightly prices. Kennel-level availability. 1-night minimum stay. | Reuses Court Booking POC's pricing primitives directly. |
| D7 | Request-to-book by default; businesses can enable instant-book per kennel type. | Hybrid gives businesses screening control without blocking high-volume operators from fast conversion. |
| D8 | Vaccination certificate upload required before a booking request can be submitted. Business reviews during 24h acceptance window. | Real pet-boarding safety concern. Document-upload-only keeps it shippable; vet integration is deferred. |
| D9 | Two-dimension ratings: service quality (1–5) and response (1–5). Both required post-stay. | Response time/rate is the most actionable KPI for a two-sided marketplace. |
| D10 | Design direction: "light and photo-forward" (Booking.com/Airbnb aesthetic). Typography-led, no decorative emojis in navigation or status accents. | User selection during brainstorming. |

## 3. Open decisions (captured for confirmation before implementation)

Each has a recommended default; final answer goes into the implementation plan.

| # | Question | Options | Recommended |
|---|---|---|---|
| O1 | Commission model | A) 12% business-only (cleaner UX) · B) 7.5% + RM4/night owner service fee (more revenue) | **A** for MVP |
| O2 | KYC rigor | Light (SSM + IC) · Medium (+ premises photo + license) · Heavy (+ in-person visit) | **Medium** |
| O3 | Payouts to businesses | Manual weekly bank transfer · iPay88 settlement API | **Manual weekly** for MVP |
| O4 | Peak calendar ownership | Platform seeds MY public+school holidays; businesses layer their own on top | **Confirmed as default** |
| O5 | Cancellation policy presets | Ship all three (Flexible / Moderate / Strict), business picks one per listing | **Confirmed as default** |

## 4. Architecture

### 4.1 Surfaces

- **Owner iOS app** — SwiftUI, iOS 17+. Browse, book, pay, review. Reuses Court Booking POC patterns.
- **Business web dashboard** — Next.js + Drizzle. Onboarding, listing CRUD, calendar, inbox, reviews, payouts.
- **Public web listings** — Next.js (same codebase, different route tree), server-rendered for SEO. Per-city landing pages + per-business profile pages with "Open in app" deep links.

### 4.2 Backend

Single **Supabase** project with:
- **Postgres** for all domain tables
- **Auth** — owners sign in with email/Apple/Google; businesses with email only (email confirmed + KYC-approved before going live)
- **Realtime** — kennel availability deltas, booking state changes, live inbox updates
- **Storage** — listing photos (public bucket), vaccination certs + KYC docs (private, RLS-guarded)
- **Edge Functions** — iPay88 webhook handler, scheduled jobs (expiry sweeps, payout calculations, peak calendar refresh)

### 4.3 Third-party integrations

- **iPay88** — FPX + card payments in MYR. Same integration pattern as Court Booking POC.
- **APNs** — push to owner iOS app for state changes.
- **Resend** (or Supabase SMTP) — transactional email for owners (receipts, cancellation notices) and businesses (new requests, acceptance-expiry nudges, receipts).

### 4.4 Five architectural invariants

1. **Single Supabase project, RLS for multi-tenancy.** Businesses are rows in a `businesses` table, not separate schemas. RLS policies scope business_admins to their own rows.
2. **Booking state machine lives in Postgres.** State transitions are SQL functions invoked via RPC. Both iOS and web call the same functions; invalid transitions error server-side.
3. **iPay88 webhook is the sole source of truth for payment state.** iOS never writes `paid`/`confirmed`; it waits for a Realtime push after the Edge Function confirms.
4. **Pet profiles live under the owner, not under bookings.** One pet → many bookings. Vaccination certs uploaded once; snapshotted at booking-request time so later edits don't rewrite history.
5. **Commission is locked in at booking-confirm time.** `platform_fee_myr` and `business_payout_myr` are stored on the booking row, immune to future pricing changes.

## 5. Roles (RBAC via Supabase RLS)

- **`owner`** — pet owner (consumer). Manages own pets, vaccination certs, bookings, reviews. Cannot see other owners or businesses' internal data.
- **`business_admin`** — admin of one or more businesses. Scoped via `business_members`. Manages listings, pricing, availability, inbox; responds to reviews.
- **`platform_admin`** — Lumarion internal staff. Approves KYC, adjusts commission rates, handles edge-case refunds. Uses Supabase Studio for MVP (no purpose-built admin UI).

Deferred role tier: **`business_staff`** (multi-user businesses with role granularity). `business_members` structurally supports it; the UI exposes only `admin` for MVP.

## 6. Data model

### 6.1 Identity and profiles

- `user_profiles` — extends `auth.users`. Fields: `display_name`, `avatar_url`, `phone`, `preferred_lang` (en/ms/zh), `primary_role`.
- `pets` — `owner_id`, `name`, `species` (dog | cat), `breed`, `age_months`, `weight_kg`, `medical_notes`, `avatar_url`.
- `vaccination_certs` — `pet_id`, `file_url`, `vaccines_covered[]`, `issued_on`, `expires_on`, `verified_by_business_id` (nullable; set when a business confirms the cert during acceptance).

### 6.2 Businesses and listings

- `businesses` — `name`, `slug` (for SEO URLs), `address`, `city`, `geo_point` (lat/lng), `description`, `cover_photo_url`, `kyc_status` (pending/verified/rejected), `kyc_documents` (JSON references into Storage), `commission_rate_bps` (default 1200 = 12%), `payout_bank_info` (encrypted), `status` (active/paused/banned).
- `business_members` — `business_id`, `user_id`, `role` (admin).
- `listings` — one row per business for MVP. Fields: `photos[]`, `amenities[]`, `house_rules`, `cancellation_policy` (flexible | moderate | strict).
- `kennel_types` — `listing_id`, `name`, `species_accepted` (dog | cat | both), `size_range` (small | medium | large), `capacity` (simultaneous occupants), `base_price_myr`, `peak_price_myr`, `instant_book` (boolean), `description`.

### 6.3 Availability

- `peak_calendar` — platform-wide peak dates (MY public holidays + school holidays), plus per-business override rows.
- `availability_overrides` — `kennel_type_id`, `date`, `manual_block` (boolean), `note`. Lets a business block individual days (maintenance, private use). Confirmed bookings auto-deduct from capacity without needing rows here.

### 6.4 Bookings

- `bookings` — `owner_id`, `business_id`, `listing_id`, `kennel_type_id`, `check_in`, `check_out`, `nights`, `subtotal_myr`, `platform_fee_myr`, `business_payout_myr`, `status` (enum, see §7), `requested_at`, `acted_at`, `payment_deadline`, `special_instructions`, `cancellation_reason`, `ipay88_reference`.
- `booking_pets` — many-to-many; supports "both my cats in one Cat Room."
- `booking_cert_snapshots` — frozen copy of vaccination-cert references at booking-request time.

### 6.5 Post-stay and ops

- `reviews` — `booking_id` (1:1), `service_rating` (1–5), `response_rating` (1–5), `text`, `posted_at`.
- `review_responses` — business's public reply to a review.
- `notifications` — `user_id`, `kind`, `payload_json`, `read_at`. In-app feed; push/email are separate side-effects.

## 7. Booking state machine

```
(request-to-book path)
 requested ──accept──▶ accepted ──pay(webhook)──▶ confirmed ──check_out_date──▶ completed
     │                    │
     │                    └─24h no payment──▶ expired
     ├─decline──▶ declined
     └─24h no action──▶ expired

(instant-book path)
 pending_payment ──pay(webhook)──▶ confirmed ──check_out_date──▶ completed
       └─15 min no payment──▶ expired

(from confirmed)
 confirmed ──owner cancels──▶ cancelled_by_owner   (refund per listing cancellation policy)
 confirmed ──business cancels──▶ cancelled_by_business (full refund + penalty flag on business)
```

**Implementation:** each transition is a Postgres function (e.g. `accept_booking(booking_id uuid)`, `confirm_payment(reference text)`). All take a row-level lock on the booking and check preconditions. Invalid transitions raise.

**Scheduled sweeps (Edge Functions, pg_cron):**
- Every 5 min: expire `requested` rows past 24h → `expired`; expire `accepted`/`pending_payment` past payment deadline → `expired`.
- Every 30 min: reconcile stuck `pending_payment` rows against iPay88 lookup API (covers lost-webhook cases).
- Every day 00:05 MY time: transition `confirmed` bookings whose `check_out` is yesterday → `completed`; send review prompts.

## 8. Owner booking flow (iOS)

Five key screens. Light/photo-forward design language, iOS Large Title typography, dark primary button, typography-driven navigation (no decorative emoji).

1. **Discover** — city (default: nearest), check-in/check-out date picker, pet selector. Single-tap "Search".
2. **Results** — scrollable list of listing cards. Filters: Price, Rating, Distance, Instant-book. Card shows hero photo, business name, rating, distance, species filter, nightly price + total.
3. **Listing detail** — photo gallery, business info, kennel-type options with pricing; sticky bottom "Continue · RM total" button.
4. **Review request** — check-in/check-out summary, pet + cert verification, notes-for-sitter textarea, price breakdown. "Send request" button disabled if pet has no valid vaccination cert; replaced by "Upload cert to continue." Instant-book listings show "Book now" and skip to payment.
5. **Status (My bookings)** — Awaiting response / Accepted-pay-now (highlighted, countdown) / Confirmed / Completed-leave-review. Realtime-driven.

**Behavior rules:**
- Vaccination gate is server-enforced: RPC that creates a booking request rejects if pet has no valid cert.
- Pay Now state is visually urgent (green tint, countdown, push notification).
- Review prompt fires on check-out day + 1 (push + in-app banner); captures both rating dimensions.

## 9. Business dashboard (web)

Six routes:

1. **Inbox** (landing) — Pending requests with countdown, today's check-ins/outs, KPI strip (Pending / Check-in / Check-out / Week revenue), response-rate/time display.
2. **Calendar** — kennel-type rows × date columns grid. Colour-coded: confirmed / pending / manual block. Click to block a day; drag to block a range.
3. **Listing** — photo upload + reorder, description editor, kennel-type CRUD (name, species, size, capacity, base price, peak price, instant-book toggle), house rules, cancellation-policy preset.
4. **Reviews** — incoming reviews with one-click "Respond" composer. Public reply appears on listing page.
5. **Payouts** — payout history, bank info, weekly payout schedule. MVP: admin sees pending payouts, platform_admin confirms bank transfer manually.
6. **Settings** — business profile, team members (future).

**Behavior rules:**
- Missing vaccination cert is flagged at card level in Inbox. "Review" button opens a flow to request the cert from the owner before accepting.
- Response countdown is visually urgent when <6h to deadline; feeds the response-time public KPI.

## 10. Payment flow (critical sequence)

```
iOS                          Supabase                    iPay88                        Business
  │
  │ 1. tap "Pay RM 420"
  ├─ rpc: create_payment_intent(booking_id) ─────▶
  │                           │ ① verify status='accepted' & owner matches
  │                           │ ② lock amount (immune to race)
  │                           │ ③ generate ref_no; return iPay88 form params
  │ ◀── form params ─────────┤
  │
  │ 2. present SFSafariView with signed iPay88 params
  │
  │ ──────────────────────────────────────────────▶
  │                                                 │ 3. user completes card/FPX
  │                                                 │ 4. iPay88 posts webhook
  │                                                 ├── POST /ipay88-webhook ──▶
  │                                                 │                           │ Edge Function:
  │                                                 │                           │ ① verify signature
  │                                                 │                           │ ② idempotency by ref_no
  │                                                 │                           │ ③ transition → confirmed
  │                                                 │                           │ ④ write platform_fee, business_payout
  │                                                 │                           │ ⑤ return 200 to iPay88
  │                                                 │
  │ ◀── Realtime push: booking.status=confirmed ─────
  │                                                                             │
  │ 5. iOS flips UI to "Confirmed"                                             │ 6. Push/email to business
```

**Invariants:**
- iOS never writes `confirmed`; only the Edge Function does.
- Idempotency by `ref_no` — duplicate webhooks are no-ops.
- Amount frozen at intent creation.
- Realtime is UX, not truth — iOS re-queries booking state on foregrounding to guard against lost pushes.
- State transition happens inside a Postgres transaction; partial writes are impossible.

## 11. Notification matrix

| Event | Owner push | Owner email | Business email | In-app feed |
|---|---|---|---|---|
| Request submitted | — | Receipt | "New request, 24h to respond" | Both |
| Request accepted | Push: "Pay now" | — | — | Both |
| Request declined | Push | Short email | — | Both |
| Payment confirmed | Push: "Booking confirmed" | Receipt w/ PDF | "Booking confirmed, prep for check-in" | Both |
| Acceptance expiring (2h left) | — | — | Email nudge | Business |
| Payment expiring (1h left) | Push | — | — | Owner |
| Booking cancelled (either side) | Push | Refund info | Status email | Both |
| Check-out day + 1 | Push: "Leave a review" | — | — | Owner |
| New review received | — | — | Email | Business |

## 12. Error handling

| Failure mode | System response |
|---|---|
| Webhook never arrives | 30-min sweep reconciles against iPay88 lookup API. |
| Business accepts after owner cancels | Postgres function rejects stale transition with clear error. |
| Race: two owners book the same kennel simultaneously | Row-level lock on `kennel_types` inside RPC; loser gets "no longer available." |
| iPay88 down | Intent creation errors cleanly; iOS shows "Payments temporarily unavailable." No partial booking state. |
| Owner's cert is expired at booking time | RPC-level precondition check; error code `CERT_EXPIRED` with remediation text. |
| Realtime disconnect | iOS re-queries booking state on foreground or pull-to-refresh. Push is the belt; Realtime the suspenders. |

## 13. Testing strategy

- **Postgres state-transition functions** — pgTAP unit tests covering every transition path, including illegal ones (expected to error).
- **iPay88 webhook** — signature verification + idempotency tested against captured real webhook payloads from iPay88 sandbox (reuse Court Booking POC's sandbox setup).
- **Owner iOS** — XCTest for view models; XCUITest for book-request flow up to iPay88 hand-off (stops there since iPay88 is external).
- **Business web** — Playwright for accept/decline/calendar-block flows.
- **End-to-end smoke** — one scripted test per environment: test-owner books → test-business accepts → iPay88 sandbox pays → DB reflects `confirmed`. Run on every deploy.

## 14. MVP phased build

Phases assume the recommended defaults for open decisions O1–O5. If any of those change before implementation begins (e.g. O1 flips to split commission, O2 to Heavy KYC), Phase 1 and Phase 3 scopes adjust accordingly.

| Phase | Scope | Success criteria |
|---|---|---|
| 0 | Supabase schema, RLS policies, state-machine functions, scheduled sweeps | `psql` transitions work for all paths; RLS blocks cross-business reads |
| 1 | Business web dashboard — auth, onboarding (KYC Medium), listing + kennel CRUD, calendar | One test business signs up end-to-end, sets prices, blocks dates |
| 2 | Owner iOS — auth, pet profile + vaccination cert upload, browse/search (read-only against seeded data) | Search returns seeded businesses in KL; cert upload works |
| 3 | Booking flow — request/accept/decline, iPay88 sandbox → prod, Realtime status | One real booking completes end-to-end via sandbox iPay88 |
| 4 | Reviews + ratings (both dimensions) | Completed booking prompts review; rating shows on listing page |
| 5 | Public web listings + transactional email polish | Google indexes city pages; confirmation emails render cleanly |
| 6 | Closed beta in KL with 5 seeded businesses | 20 real bookings go through end-to-end without manual intervention |

Full stack reuses Court Booking POC's iPay88 integration + `poc-booking-system` patterns. Phases 0–3 are the critical path; 4–6 can overlap.

## 15. Deferred scope (NOT in this slice)

- **Pet clinics** — separate spec, veterinary/regulatory domain.
- **In-app chat** — only "notes for sitter" field at booking-request time. Full chat is a later slice.
- **Disputes & refund arbitration** — edge cases handled manually by platform_admin in Supabase Studio.
- **Multi-staff roles per business** — one admin per business in MVP; schema supports more.
- **Platform admin web UI** — Supabase Studio for MVP.
- **Android app** — iOS only at launch.
- **Adjacent pet services** — dog walking, day-care, grooming. Separate slices.
- **Insurance product.**
- **Individual/non-business sitters** — Option A from Question 1 of brainstorming.
- **Trust & safety subsystem** — ratings are in; moderation, dispute workflow, ID verification for owners are deferred.

## 16. Glossary

- **Listing** — a single row per business representing their boarding offering.
- **Kennel type** — a variant inside a listing (e.g. Small Dog Suite). The actual bookable unit.
- **Instant-book** — listing flag that skips the request-acceptance step; owner pays immediately.
- **Peak/off-peak** — per-date multiplier driven by `peak_calendar`.
- **Response rate** — fraction of requests a business responded to (accept or decline) within 24h. Public KPI.
- **Response time** — mean time-to-action on requests. Public KPI.
