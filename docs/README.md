# PetBnB docs

Reviewer-friendly snapshot of everything driving the implementation.

- [`architecture.md`](./architecture.md) — high-level system overview: clients, backend, data model, state machine, RLS, test coverage, gotchas.
- [`spec.md`](./spec.md) — original design spec (2026-04-22) covering scope, decisions, open questions, MVP cut.
- [`plans/`](./plans/) — per-phase implementation plans, in build order:
  1. Phase 0 — Supabase schema + state machine
  2. Phase 1a — Next.js scaffold + auth + onboarding RPC
  3. Phase 1b — KYC upload (Storage RLS)
  4. Phase 1c — Listing editor + kennel CRUD + photos
  5. Phase 1d — Real inbox + calendar/availability grid
  6. Phase 2a — iOS scaffold + auth + pet profiles
  7. Phase 2b — iOS Discover + browse + listing detail
  8. Phase 2c — iOS booking + payment-intent stub + My Bookings
  9. Phase 2d — iPay88 Edge Function webhook + iOS Realtime

Status summary and run instructions live in the project root [README.md](../README.md).
