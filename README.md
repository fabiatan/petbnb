# PetBnB

Two-sided marketplace for Malaysian pet boarding. iOS app for owners + Next.js web dashboard for businesses; shared Supabase backend.

**Spec:** `../docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`

## Status

- [x] **Phase 0** — Supabase schema, RLS, state-machine functions, pg_cron sweeps. See `supabase/README.md`.
- [ ] Phase 1 — Business web dashboard (Next.js)
- [ ] Phase 2 — iOS owner app (SwiftUI)
- [ ] Phase 3 — iPay88 integration
- [ ] Phase 4 — Reviews + ratings wiring
- [ ] Phase 5 — Public SEO listings + transactional email
- [ ] Phase 6 — Closed beta in KL

## Local dev (Phase 0)

```bash
cd supabase
supabase start
supabase db reset        # applies migrations + seed.sql
supabase test db         # runs pgTAP suite
./scripts/verify-phase0.sh
```
