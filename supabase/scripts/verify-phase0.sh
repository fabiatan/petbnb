#!/usr/bin/env bash
# Phase 0 acceptance: exercise the full state machine end-to-end on a fresh local DB.
# Exits non-zero on any failure.

set -euo pipefail

# Ensure psql is on PATH (Homebrew libpq not linked by default on Apple Silicon)
export PATH="/opt/homebrew/opt/libpq/bin:${PATH}"

DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
OWNER='10000000-0000-0000-0000-000000000001'
KENNEL_INSTANT='60000000-0000-0000-0000-000000000001'
KENNEL_REQUEST='60000000-0000-0000-0000-000000000002'
PET='30000000-0000-0000-0000-000000000001'

step() { printf "\n\033[1;34m→ %s\033[0m\n" "$*"; }

step "1. Reset DB"
cd "$(dirname "$0")/.."
supabase db reset

step "2. Run pgTAP tests"
supabase test db

step "3. Instant-book happy path"
BOOKING_ID=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='${OWNER}';
  SET LOCAL role='authenticated';
  SELECT create_instant_booking(
    '${KENNEL_INSTANT}'::uuid,
    ARRAY['${PET}'::uuid],
    '2027-06-01'::date, '2027-06-03'::date, 'e2e'
  );
" | tail -1)
echo "booking=${BOOKING_ID}"

REF=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='${OWNER}';
  SET LOCAL role='authenticated';
  SELECT create_payment_intent('${BOOKING_ID}'::uuid);
" | tail -1)
echo "ref=${REF}"

psql "$DB" -c "SELECT confirm_payment('${REF}', 160::numeric);"

STATUS=$(psql "$DB" -Atc "SELECT status FROM bookings WHERE id='${BOOKING_ID}';")
[[ "$STATUS" == "confirmed" ]] || { echo "FAIL: status is ${STATUS}, want confirmed"; exit 1; }
echo "OK instant-book → confirmed"

step "4. Request-to-book happy path"
REQ_ID=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='${OWNER}';
  SET LOCAL role='authenticated';
  SELECT create_booking_request(
    '${KENNEL_REQUEST}'::uuid,
    ARRAY['${PET}'::uuid],
    '2027-07-01'::date, '2027-07-03'::date, NULL
  );
" | tail -1)
echo "request=${REQ_ID}"

# Admin accepts
psql "$DB" -c "
  SET LOCAL request.jwt.claim.sub='20000000-0000-0000-0000-000000000001';
  SET LOCAL role='authenticated';
  SELECT accept_booking('${REQ_ID}'::uuid);
"

# Owner pays
REQ_REF=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='${OWNER}';
  SET LOCAL role='authenticated';
  SELECT create_payment_intent('${REQ_ID}'::uuid);
" | tail -1)
psql "$DB" -c "SELECT confirm_payment('${REQ_REF}', 240::numeric);"

STATUS=$(psql "$DB" -Atc "SELECT status FROM bookings WHERE id='${REQ_ID}';")
[[ "$STATUS" == "confirmed" ]] || { echo "FAIL: request status is ${STATUS}"; exit 1; }
echo "OK request-to-book → confirmed"

step "5. RLS cross-business isolation"
COUNT=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='20000000-0000-0000-0000-000000000002';
  SET LOCAL role='authenticated';
  SELECT count(*) FROM bookings;
" | tail -1)
[[ "$COUNT" == "0" ]] || { echo "FAIL: Biz B admin sees ${COUNT} bookings, want 0"; exit 1; }
echo "OK Biz B admin sees 0 bookings"

step "6. Sweeps are scheduled"
JOBS=$(psql "$DB" -Atc "SELECT count(*) FROM cron.job WHERE jobname LIKE 'petbnb_%';")
[[ "$JOBS" == "4" ]] || { echo "FAIL: ${JOBS} cron jobs, want 4"; exit 1; }
echo "OK 4 petbnb_* cron jobs scheduled"

step "All Phase 0 checks passed ✓"
