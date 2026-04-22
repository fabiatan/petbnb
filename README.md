# PetBnB

Two-sided marketplace connecting Malaysian pet owners with commercial boarding businesses. iOS app for owners + Next.js web dashboard for businesses; shared Supabase backend.

**Spec:** `../docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`
**Phase 0 plan:** `../docs/superpowers/plans/2026-04-22-petbnb-phase0-schema-and-state-machine.md`

## Phase 0 — run it locally

```bash
cd supabase
supabase start          # boots Postgres + Studio at :54323
supabase db reset       # applies all migrations against fresh DB
supabase test db        # runs pgTAP suite
```

Phase 0 is backend-only (schema + state machine + RLS + sweeps). Web dashboard and iOS come in later phases.
