# PetBnB

Two-sided marketplace for Malaysian pet boarding. iOS app for owners + Next.js web dashboard for businesses; shared Supabase backend.

**Spec:** `../docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`

## Status

- [x] **Phase 0** — Supabase schema, RLS, state-machine functions, pg_cron sweeps. See `supabase/README.md`.
- [x] **Phase 1a** — Next.js scaffold, Supabase Auth, Drizzle schema, business onboarding RPC. See `web/README.md`.
- [x] **Phase 1b** — KYC upload and documents review
- [ ] Phase 1c — Listing editor + kennel CRUD + photo management
- [ ] Phase 1d — Calendar / availability grid + real Inbox
- [ ] Phase 2 — iOS owner app (SwiftUI)
- [ ] Phase 3 — iPay88 integration
- [ ] Phase 4 — Reviews + ratings wiring
- [ ] Phase 5 — Public SEO listings + transactional email
- [ ] Phase 6 — Closed beta in KL

## Local dev

### Supabase (runs from project root)

```bash
supabase start           # boots Postgres + Studio at :54323
supabase db reset        # applies migrations + seed.sql
supabase test db         # runs pgTAP suite
./supabase/scripts/verify-phase0.sh
```

### Web app (runs from `web/`)

```bash
cd web
cp .env.local.example .env.local
# paste the anon key printed by `supabase status` into .env.local
pnpm install
pnpm dev                 # http://localhost:3000
pnpm exec playwright test  # E2E smoke test
```
