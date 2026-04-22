# PetBnB Supabase (Phase 0)

Single Supabase project. Schema, RLS policies, booking state-machine functions, scheduled sweeps.

## Layout

```
migrations/          forward-only, numbered
  001_enums.sql
  002_identity_tables.sql
  003_business_tables.sql
  004_availability_tables.sql
  005_booking_tables.sql
  006_post_stay_tables.sql
  007_indexes.sql
  008_rls_policies.sql
  009_helper_functions.sql
  010_state_transitions.sql
  011_scheduled_sweeps.sql
  012_seed_peak_calendar.sql
tests/               pgTAP — run via `supabase test db`
seed.sql             dev-only seed (auto-applied by db reset)
scripts/verify-phase0.sh   end-to-end acceptance check
```

## State machine

```
request-to-book:   requested -> accepted -> pending_payment -> confirmed -> completed
                       |           |
                       +-declined  +-> expired (no payment)
                       +-expired (no response)

instant-book:      pending_payment -> confirmed -> completed
                         +-> expired (no payment, 15min)

from confirmed:    -> cancelled_by_owner
                   -> cancelled_by_business
```

Every transition is a SECURITY DEFINER SQL function in `010_state_transitions.sql`. RLS allows only SELECT on `bookings`; all writes go through RPC.

## Scheduled sweeps

Four pg_cron jobs (see `011_scheduled_sweeps.sql`):

| Job | Schedule (UTC) | Purpose |
|---|---|---|
| `petbnb_expire_requests` | */5 * * * * | Expire requested > 24h |
| `petbnb_expire_payments` | */5 * * * * | Expire accepted/pending_payment past deadline |
| `petbnb_complete_past` | 5 16 * * * (00:05 MY) | Mark confirmed+past-checkout as completed; send review_prompt |
| `petbnb_reconcile_payments` | */30 * * * * | Stub in Phase 0; Phase 3 calls iPay88 lookup |

## Handoff to Phase 1

- `create_booking_request`, `accept_booking`, `decline_booking`, `create_instant_booking`, `create_payment_intent`, `cancel_booking_by_owner`, `cancel_booking_by_business` are the public RPC surface for the web dashboard.
- `confirm_payment(ref, amount)` is called by the iPay88 webhook Edge Function (Phase 3).
- Drizzle schema for Next.js should be hand-written in Phase 1 to match the tables here; do not use drizzle-kit introspection against the live DB as it will miss our SECURITY DEFINER functions.
