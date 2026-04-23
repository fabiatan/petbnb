# PetBnB Phase 0 — Supabase Schema & State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the PetBnB Supabase project with full schema, RLS policies, booking state-machine SQL functions, pgTAP tests, and scheduled sweep jobs — so that later phases (business dashboard, iOS, iPay88) can treat the backend as a trusted, tested foundation.

**Architecture:** Single Supabase project. Postgres as the state-machine runtime: every booking transition is a `SECURITY DEFINER` function called via RPC. RLS scopes owners to their own data and business_admins to their own businesses. Scheduled sweeps run via `pg_cron`. All changes are TDD-driven using pgTAP.

**Tech Stack:**
- Supabase CLI (`supabase` v1.x)
- PostgreSQL 15 (bundled by Supabase)
- pgTAP for SQL unit tests (bundled by Supabase)
- `pg_cron` extension for scheduled sweeps (enabled by default on Supabase)
- `uuid-ossp` extension for UUID primary keys
- Docker (required for `supabase start` local dev)

**Spec reference:** `docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`

**Scope excluded from Phase 0** (done in later phases):
- Business onboarding / KYC workflow UI — Phase 1 (dashboard)
- Next.js web app and Drizzle ORM schema — Phase 1
- iOS app — Phase 2
- Real iPay88 integration — Phase 3 (this phase stubs the webhook handler)
- `payout_bank_info` encryption via pgsodium — Phase 5 (before real payouts). Stored as plain JSONB for now with a comment.

**Phase 0 success criteria:**
1. `supabase db reset` applies all migrations cleanly from scratch.
2. `supabase test db` passes — every booking state transition (valid + invalid) has a pgTAP test.
3. An RLS smoke test shows a business_admin from Business A cannot read Business B's bookings.
4. `pg_cron` jobs are scheduled and visible in `cron.job`.
5. Peak calendar is seeded with MY public + school holidays for 2026 and 2027.

---

## File structure

Phase 0 creates a new project at `/Users/fabian/CodingProject/Primary/PetBnB/`:

```
PetBnB/
├── .gitignore
├── README.md
└── supabase/
    ├── config.toml
    ├── seed.sql
    ├── migrations/
    │   ├── 001_enums.sql
    │   ├── 002_identity_tables.sql
    │   ├── 003_business_tables.sql
    │   ├── 004_availability_tables.sql
    │   ├── 005_booking_tables.sql
    │   ├── 006_post_stay_tables.sql
    │   ├── 007_indexes.sql
    │   ├── 008_rls_policies.sql
    │   ├── 009_helper_functions.sql
    │   ├── 010_state_transitions.sql
    │   ├── 011_scheduled_sweeps.sql
    │   └── 012_seed_peak_calendar.sql
    └── tests/
        ├── 000_harness.sql
        ├── 001_schema.sql
        ├── 002_rls.sql
        ├── 003_helper_functions.sql
        ├── 004_booking_request.sql
        ├── 005_booking_accept_decline.sql
        ├── 006_booking_instant.sql
        ├── 007_booking_payment.sql
        ├── 008_booking_cancel.sql
        └── 009_sweeps.sql
```

**File responsibilities:**
- Each migration in `migrations/` is idempotent and forward-only. Numbered by concern, not date, to match the Court Booking POC's established convention.
- Each test in `tests/` targets one cluster of behaviour. `000_harness.sql` provides setup helpers reused by every other test.

---

## Task 0: Bootstrap project

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/.gitignore`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/README.md`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/supabase/config.toml` (via `supabase init`)

- [ ] **Step 1: Verify prerequisites**

Run each; all must succeed:
```bash
docker --version        # >= 20.x
supabase --version      # >= 1.150
git --version
```

If Supabase CLI is missing: `brew install supabase/tap/supabase`.

- [ ] **Step 2: Create project directory and initialize git**

```bash
mkdir -p /Users/fabian/CodingProject/Primary/PetBnB
cd /Users/fabian/CodingProject/Primary/PetBnB
git init -b main
```

Expected: `Initialized empty Git repository in …/PetBnB/.git/`

- [ ] **Step 3: Write .gitignore**

Create `/Users/fabian/CodingProject/Primary/PetBnB/.gitignore`:
```
# Supabase local dev
supabase/.branches
supabase/.temp
supabase/.env
supabase/.env.local

# OS / editor
.DS_Store
*.swp
.idea/
.vscode/

# Node (for later phases)
node_modules/
.next/
dist/
```

- [ ] **Step 4: Write README**

Create `/Users/fabian/CodingProject/Primary/PetBnB/README.md`:
```markdown
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
```

- [ ] **Step 5: supabase init**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase init
```

Accept defaults. This creates `supabase/config.toml` and `supabase/seed.sql`.

- [ ] **Step 6: Enable pg_cron + pgTAP in config.toml**

Edit `/Users/fabian/CodingProject/Primary/PetBnB/supabase/config.toml`. Find the `[db]` section and add under it (or uncomment if present):
```toml
[db.pooler]
enabled = false

[db.seed]
enabled = true
sql_paths = ["./seed.sql"]
```

Find the `[edge_runtime]` section (leave defaults).

Add or confirm this top-level section exists:
```toml
[db]
major_version = 15

[db.pooler]
enabled = false
```

Supabase local enables `pg_cron`, `pgcrypto`, and `pgtap` by default in local dev. Confirm by running the next step.

- [ ] **Step 7: supabase start and verify**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase start
```

Expected output ends with:
```
API URL: http://127.0.0.1:54321
DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
Studio URL: http://127.0.0.1:54323
```

Confirm extensions:
```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT extname FROM pg_extension WHERE extname IN ('pg_cron','pgtap','pgcrypto','uuid-ossp');"
```
Expected: 4 rows.

- [ ] **Step 8: Commit bootstrap**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add .gitignore README.md supabase/
git commit -m "chore: bootstrap PetBnB Supabase project"
```

---

## Task 1: Enums migration

Creates all enum types used across schema. Doing enums first means later migrations can reference them without forward declarations.

**Files:**
- Create: `supabase/migrations/001_enums.sql`

- [ ] **Step 1: Write 001_enums.sql**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/001_enums.sql`:
```sql
-- User role for user_profiles.primary_role
CREATE TYPE user_role AS ENUM (
  'owner',
  'business_admin',
  'platform_admin'
);

-- Business lifecycle
CREATE TYPE kyc_status AS ENUM (
  'pending',
  'verified',
  'rejected'
);

CREATE TYPE business_status AS ENUM (
  'active',
  'paused',
  'banned'
);

-- Animal species accepted by a kennel type
CREATE TYPE species_accepted AS ENUM (
  'dog',
  'cat',
  'both'
);

CREATE TYPE species AS ENUM (
  'dog',
  'cat'
);

CREATE TYPE size_range AS ENUM (
  'small',
  'medium',
  'large'
);

-- Per-listing cancellation policy
CREATE TYPE cancellation_policy AS ENUM (
  'flexible',
  'moderate',
  'strict'
);

-- Booking state machine (see spec §7)
CREATE TYPE booking_status AS ENUM (
  'requested',
  'accepted',
  'declined',
  'pending_payment',
  'expired',
  'confirmed',
  'completed',
  'cancelled_by_owner',
  'cancelled_by_business'
);

-- Reason a booking reached a terminal state
CREATE TYPE booking_terminal_reason AS ENUM (
  'no_response_24h',
  'no_payment_24h',
  'no_payment_15min_instant',
  'owner_cancelled',
  'business_cancelled',
  'payment_failed'
);

-- Notification kinds (in-app feed)
CREATE TYPE notification_kind AS ENUM (
  'request_submitted',
  'request_accepted',
  'request_declined',
  'payment_confirmed',
  'acceptance_expiring',
  'payment_expiring',
  'booking_cancelled',
  'review_prompt',
  'review_received'
);
```

- [ ] **Step 2: Apply migration**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

Expected: no errors, ends with `Finished supabase db reset on branch ...`.

- [ ] **Step 3: Verify enums exist**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\dT+ booking_status"
```
Expected output contains all 9 enum values.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/001_enums.sql
git commit -m "feat(db): add enum types"
```

---

## Task 2: Identity tables

Spec §6.1. Tables: `user_profiles`, `pets`, `vaccination_certs`.

**Files:**
- Create: `supabase/migrations/002_identity_tables.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/002_identity_tables.sql`:
```sql
-- user_profiles: extends auth.users with app-level fields
CREATE TABLE user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  avatar_url text,
  phone text,
  preferred_lang text NOT NULL DEFAULT 'en' CHECK (preferred_lang IN ('en','ms','zh')),
  primary_role user_role NOT NULL DEFAULT 'owner',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- pets: owned by a user_profile
CREATE TABLE pets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  species species NOT NULL,
  breed text,
  age_months integer CHECK (age_months >= 0 AND age_months < 600),
  weight_kg numeric(5,2) CHECK (weight_kg > 0 AND weight_kg < 200),
  medical_notes text,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- vaccination_certs: file reference + expiry
CREATE TABLE vaccination_certs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pet_id uuid NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
  file_url text NOT NULL,
  vaccines_covered text[] NOT NULL DEFAULT ARRAY[]::text[],
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  verified_by_business_id uuid,    -- FK added in 003; deferred to avoid circular order
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);

-- Auto-update updated_at on user_profiles and pets
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_user_profiles
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_pets
  BEFORE UPDATE ON pets
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```
Expected: no errors.

- [ ] **Step 3: Verify schema**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\d user_profiles" -c "\d pets" -c "\d vaccination_certs"
```
Expected: all three tables appear with the listed columns.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/002_identity_tables.sql
git commit -m "feat(db): add identity tables (user_profiles, pets, vaccination_certs)"
```

---

## Task 3: Business tables

Spec §6.2. Tables: `businesses`, `business_members`, `listings`, `kennel_types`. Also finalize the forward-declared FK from `vaccination_certs.verified_by_business_id`.

**Files:**
- Create: `supabase/migrations/003_business_tables.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/003_business_tables.sql`:
```sql
CREATE TABLE businesses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  geo_point point,
  description text,
  cover_photo_url text,
  logo_url text,
  kyc_status kyc_status NOT NULL DEFAULT 'pending',
  kyc_documents jsonb NOT NULL DEFAULT '{}'::jsonb,
  commission_rate_bps integer NOT NULL DEFAULT 1200 CHECK (commission_rate_bps BETWEEN 0 AND 10000),
  payout_bank_info jsonb NOT NULL DEFAULT '{}'::jsonb,    -- Phase 5: wrap with pgsodium before real payouts
  status business_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_businesses
  BEFORE UPDATE ON businesses
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- business_members: join table (user <-> business)
CREATE TABLE business_members (
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, user_id)
);

-- listings: one per business (for MVP)
CREATE TABLE listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL UNIQUE REFERENCES businesses(id) ON DELETE CASCADE,
  photos text[] NOT NULL DEFAULT ARRAY[]::text[],
  amenities text[] NOT NULL DEFAULT ARRAY[]::text[],
  house_rules text,
  cancellation_policy cancellation_policy NOT NULL DEFAULT 'moderate',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_listings
  BEFORE UPDATE ON listings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- kennel_types: variants inside a listing
CREATE TABLE kennel_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  name text NOT NULL,
  species_accepted species_accepted NOT NULL,
  size_range size_range NOT NULL,
  capacity integer NOT NULL CHECK (capacity > 0),
  base_price_myr numeric(10,2) NOT NULL CHECK (base_price_myr >= 0),
  peak_price_myr numeric(10,2) NOT NULL CHECK (peak_price_myr >= 0),
  instant_book boolean NOT NULL DEFAULT false,
  description text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_kennel_types
  BEFORE UPDATE ON kennel_types
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- Add the deferred FK from vaccination_certs -> businesses
ALTER TABLE vaccination_certs
  ADD CONSTRAINT vaccination_certs_verified_by_business_id_fkey
  FOREIGN KEY (verified_by_business_id) REFERENCES businesses(id) ON DELETE SET NULL;
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\d businesses" -c "\d listings" -c "\d kennel_types"
```
Expected: tables exist with constraints shown.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/003_business_tables.sql
git commit -m "feat(db): add business, listing, kennel_type tables"
```

---

## Task 4: Availability tables

Spec §6.3. Tables: `peak_calendar`, `availability_overrides`.

**Files:**
- Create: `supabase/migrations/004_availability_tables.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/004_availability_tables.sql`:
```sql
-- Peak dates. Platform rows have business_id = NULL; businesses layer overrides on top.
CREATE TABLE peak_calendar (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid REFERENCES businesses(id) ON DELETE CASCADE,
  date date NOT NULL,
  label text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One entry per (business_id, date) pair; NULL business_id is the platform row.
CREATE UNIQUE INDEX peak_calendar_global_uidx
  ON peak_calendar (date)
  WHERE business_id IS NULL;

CREATE UNIQUE INDEX peak_calendar_business_uidx
  ON peak_calendar (business_id, date)
  WHERE business_id IS NOT NULL;

-- Manual blocks by a business on a specific kennel+date.
CREATE TABLE availability_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kennel_type_id uuid NOT NULL REFERENCES kennel_types(id) ON DELETE CASCADE,
  date date NOT NULL,
  manual_block boolean NOT NULL DEFAULT true,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kennel_type_id, date)
);
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\d peak_calendar" -c "\d availability_overrides"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/004_availability_tables.sql
git commit -m "feat(db): add availability tables"
```

---

## Task 5: Booking tables

Spec §6.4. Tables: `bookings`, `booking_pets`, `booking_cert_snapshots`.

**Files:**
- Create: `supabase/migrations/005_booking_tables.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/005_booking_tables.sql`:
```sql
CREATE TABLE bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES user_profiles(id),
  business_id uuid NOT NULL REFERENCES businesses(id),
  listing_id uuid NOT NULL REFERENCES listings(id),
  kennel_type_id uuid NOT NULL REFERENCES kennel_types(id),
  check_in date NOT NULL,
  check_out date NOT NULL,
  nights integer NOT NULL,
  subtotal_myr numeric(10,2) NOT NULL CHECK (subtotal_myr >= 0),
  platform_fee_myr numeric(10,2) NOT NULL DEFAULT 0 CHECK (platform_fee_myr >= 0),
  business_payout_myr numeric(10,2) NOT NULL DEFAULT 0 CHECK (business_payout_myr >= 0),
  status booking_status NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  acted_at timestamptz,
  payment_deadline timestamptz,
  special_instructions text,
  terminal_reason booking_terminal_reason,
  ipay88_reference text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (check_out > check_in),
  CHECK (nights = (check_out - check_in))
);

CREATE TRIGGER set_updated_at_bookings
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- Pets covered by a booking (many-to-many)
CREATE TABLE booking_pets (
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  pet_id uuid NOT NULL REFERENCES pets(id),
  PRIMARY KEY (booking_id, pet_id)
);

-- Frozen vaccination cert references per booking
CREATE TABLE booking_cert_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  pet_id uuid NOT NULL REFERENCES pets(id),
  vaccination_cert_id uuid NOT NULL REFERENCES vaccination_certs(id),
  file_url text NOT NULL,
  expires_on date NOT NULL,
  snapshotted_at timestamptz NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\d bookings"
```
Expected: booking table with all columns and check constraints.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/005_booking_tables.sql
git commit -m "feat(db): add booking tables"
```

---

## Task 6: Post-stay & ops tables

Spec §6.5. Tables: `reviews`, `review_responses`, `notifications`.

**Files:**
- Create: `supabase/migrations/006_post_stay_tables.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/006_post_stay_tables.sql`:
```sql
CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES businesses(id),
  owner_id uuid NOT NULL REFERENCES user_profiles(id),
  service_rating integer NOT NULL CHECK (service_rating BETWEEN 1 AND 5),
  response_rating integer NOT NULL CHECK (response_rating BETWEEN 1 AND 5),
  text text,
  posted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL UNIQUE REFERENCES reviews(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES businesses(id),
  text text NOT NULL,
  posted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  kind notification_kind NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "\d reviews" -c "\d notifications"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/006_post_stay_tables.sql
git commit -m "feat(db): add post-stay and notifications tables"
```

---

## Task 7: Indexes

The state-machine functions query by (kennel_type_id, date range), (owner_id, status), (business_id, status). Add indexes now so pgTAP tests run fast and later apps don't have N+1 scan pain.

**Files:**
- Create: `supabase/migrations/007_indexes.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/007_indexes.sql`:
```sql
CREATE INDEX pets_owner_id_idx ON pets(owner_id);
CREATE INDEX vaccination_certs_pet_id_idx ON vaccination_certs(pet_id);
CREATE INDEX vaccination_certs_expires_on_idx ON vaccination_certs(expires_on);

CREATE INDEX business_members_user_id_idx ON business_members(user_id);
CREATE INDEX business_members_business_id_idx ON business_members(business_id);

CREATE INDEX listings_business_id_idx ON listings(business_id);
CREATE INDEX kennel_types_listing_id_idx ON kennel_types(listing_id);
CREATE INDEX kennel_types_active_idx ON kennel_types(listing_id) WHERE active;

CREATE INDEX bookings_owner_id_idx ON bookings(owner_id);
CREATE INDEX bookings_business_id_idx ON bookings(business_id);
CREATE INDEX bookings_kennel_type_status_idx ON bookings(kennel_type_id, status);
CREATE INDEX bookings_status_requested_idx ON bookings(status, requested_at) WHERE status = 'requested';
CREATE INDEX bookings_status_payment_deadline_idx ON bookings(status, payment_deadline) WHERE status IN ('accepted','pending_payment');
CREATE INDEX bookings_status_check_out_idx ON bookings(status, check_out) WHERE status = 'confirmed';

CREATE INDEX booking_pets_booking_id_idx ON booking_pets(booking_id);

CREATE INDEX notifications_user_created_idx ON notifications(user_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications(user_id) WHERE read_at IS NULL;

CREATE INDEX peak_calendar_date_idx ON peak_calendar(date);
CREATE INDEX availability_overrides_kennel_date_idx ON availability_overrides(kennel_type_id, date);
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT indexname FROM pg_indexes WHERE schemaname='public' AND indexname LIKE 'bookings%' ORDER BY indexname;"
```
Expected: all six `bookings_*` indexes listed.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/007_indexes.sql
git commit -m "feat(db): add indexes for state-machine and dashboard queries"
```

---

## Task 8: RLS policies

Spec §4.4 invariant 1. Owners see own pets/certs/bookings/reviews. Business_admins see rows for their business only. `SECURITY DEFINER` state-transition functions (written later) bypass RLS deliberately; normal queries do not.

**Files:**
- Create: `supabase/migrations/008_rls_policies.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/008_rls_policies.sql`:
```sql
-- Enable RLS on every table
ALTER TABLE user_profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE pets                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE vaccination_certs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE businesses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_members      ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE kennel_types          ENABLE ROW LEVEL SECURITY;
ALTER TABLE peak_calendar         ENABLE ROW LEVEL SECURITY;
ALTER TABLE availability_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_pets          ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_cert_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews               ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_responses      ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications         ENABLE ROW LEVEL SECURITY;

-- Helper: is the current auth.uid() a member of this business?
CREATE OR REPLACE FUNCTION is_business_member(p_business_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members
    WHERE business_id = p_business_id AND user_id = auth.uid()
  );
$$;

-- user_profiles: users see + update own row
CREATE POLICY user_profiles_self_select ON user_profiles
  FOR SELECT USING (id = auth.uid());
CREATE POLICY user_profiles_self_update ON user_profiles
  FOR UPDATE USING (id = auth.uid());
CREATE POLICY user_profiles_self_insert ON user_profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- pets: owner-only
CREATE POLICY pets_owner ON pets
  FOR ALL USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- vaccination_certs: owner via join on pet
CREATE POLICY vax_owner ON vaccination_certs
  FOR ALL USING (
    EXISTS (SELECT 1 FROM pets WHERE pets.id = vaccination_certs.pet_id AND pets.owner_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM pets WHERE pets.id = vaccination_certs.pet_id AND pets.owner_id = auth.uid())
  );

-- businesses: public-read on verified+active rows (for discovery);
-- business_members have full access to their own rows.
CREATE POLICY businesses_public_read ON businesses
  FOR SELECT USING (kyc_status = 'verified' AND status = 'active');
CREATE POLICY businesses_member_all ON businesses
  FOR ALL USING (is_business_member(id))
  WITH CHECK (is_business_member(id));

-- business_members: member sees own business's member list
CREATE POLICY business_members_member_read ON business_members
  FOR SELECT USING (is_business_member(business_id));

-- listings: public read; members full
CREATE POLICY listings_public_read ON listings
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM businesses b WHERE b.id = listings.business_id
            AND b.kyc_status = 'verified' AND b.status = 'active')
  );
CREATE POLICY listings_member_all ON listings
  FOR ALL USING (is_business_member(business_id))
  WITH CHECK (is_business_member(business_id));

-- kennel_types: public read (via listing); members full
CREATE POLICY kennel_types_public_read ON kennel_types
  FOR SELECT USING (
    active AND EXISTS (
      SELECT 1 FROM listings l JOIN businesses b ON b.id = l.business_id
      WHERE l.id = kennel_types.listing_id
        AND b.kyc_status = 'verified' AND b.status = 'active'
    )
  );
CREATE POLICY kennel_types_member_all ON kennel_types
  FOR ALL USING (
    EXISTS (SELECT 1 FROM listings l WHERE l.id = kennel_types.listing_id AND is_business_member(l.business_id))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM listings l WHERE l.id = kennel_types.listing_id AND is_business_member(l.business_id))
  );

-- peak_calendar: public rows readable to all; per-business rows scoped
CREATE POLICY peak_calendar_public_read ON peak_calendar
  FOR SELECT USING (business_id IS NULL OR is_business_member(business_id));
CREATE POLICY peak_calendar_member_write ON peak_calendar
  FOR ALL USING (business_id IS NOT NULL AND is_business_member(business_id))
  WITH CHECK (business_id IS NOT NULL AND is_business_member(business_id));

-- availability_overrides: members-only
CREATE POLICY availability_overrides_member_all ON availability_overrides
  FOR ALL USING (
    EXISTS (SELECT 1 FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
            WHERE kt.id = availability_overrides.kennel_type_id
              AND is_business_member(l.business_id))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
            WHERE kt.id = availability_overrides.kennel_type_id
              AND is_business_member(l.business_id))
  );

-- bookings: owner sees own; business_admin sees own business's bookings
CREATE POLICY bookings_owner_read ON bookings
  FOR SELECT USING (owner_id = auth.uid());
CREATE POLICY bookings_business_read ON bookings
  FOR SELECT USING (is_business_member(business_id));
-- No INSERT/UPDATE policies: all mutations go through SECURITY DEFINER functions.

-- booking_pets: via booking join
CREATE POLICY booking_pets_read ON booking_pets
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM bookings b WHERE b.id = booking_pets.booking_id
            AND (b.owner_id = auth.uid() OR is_business_member(b.business_id)))
  );

-- booking_cert_snapshots: same visibility as parent booking
CREATE POLICY cert_snapshots_read ON booking_cert_snapshots
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM bookings b WHERE b.id = booking_cert_snapshots.booking_id
            AND (b.owner_id = auth.uid() OR is_business_member(b.business_id)))
  );

-- reviews: public read (verified businesses only); owner writes
CREATE POLICY reviews_public_read ON reviews
  FOR SELECT USING (true);
CREATE POLICY reviews_owner_insert ON reviews
  FOR INSERT WITH CHECK (owner_id = auth.uid());

-- review_responses: public read; business members write
CREATE POLICY review_responses_public_read ON review_responses
  FOR SELECT USING (true);
CREATE POLICY review_responses_member_write ON review_responses
  FOR ALL USING (is_business_member(business_id))
  WITH CHECK (is_business_member(business_id));

-- notifications: recipient only
CREATE POLICY notifications_recipient ON notifications
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
```

- [ ] **Step 3: Verify RLS is enabled**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
```
Expected: `rowsecurity = t` for every PetBnB table.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/008_rls_policies.sql
git commit -m "feat(db): add RLS policies for all tables"
```

---

## Task 9: pgTAP harness + schema smoke test

Sets up the test harness and proves `supabase test db` wiring works end-to-end.

**Files:**
- Create: `supabase/tests/000_harness.sql`
- Create: `supabase/tests/001_schema.sql`

- [ ] **Step 1: Write harness**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/000_harness.sql`:
```sql
-- Harness: helpers reused across test files.
-- Supabase test runner wraps each test file in a transaction that's rolled back,
-- so seed data created here is isolated to the file using it.

BEGIN;
SELECT plan(1);
SELECT ok(true, 'harness loads');
SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Write 001_schema.sql smoke test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/001_schema.sql`:
```sql
BEGIN;
SELECT plan(8);

SELECT has_table('public', 'user_profiles');
SELECT has_table('public', 'pets');
SELECT has_table('public', 'businesses');
SELECT has_table('public', 'listings');
SELECT has_table('public', 'kennel_types');
SELECT has_table('public', 'bookings');
SELECT has_table('public', 'reviews');
SELECT has_enum('public', 'booking_status');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```
Expected: `ok` lines ending with `9..9 tests ok` (1 from harness + 8 from schema).

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/000_harness.sql supabase/tests/001_schema.sql
git commit -m "test(db): add pgTAP harness and schema smoke test"
```

---

## Task 10: RLS isolation test — cross-business read is blocked

This is the Phase 0 success criterion #3. Simulates two users, each a member of a different business, and proves business A cannot read business B's bookings.

**Files:**
- Create: `supabase/tests/002_rls.sql`

- [ ] **Step 1: Write failing RLS test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/002_rls.sql`:
```sql
BEGIN;
SELECT plan(4);

-- Create two auth users
INSERT INTO auth.users (id, email)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@biz-a.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@biz-b.test');

INSERT INTO user_profiles (id, display_name, primary_role)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Alice', 'business_admin'),
  ('22222222-2222-2222-2222-222222222222', 'Bob', 'business_admin');

-- Two businesses
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Biz A', 'biz-a', '1 A St', 'KL', 'WP', 'verified', 'active'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Biz B', 'biz-b', '1 B St', 'KL', 'WP', 'verified', 'active');

INSERT INTO business_members (business_id, user_id) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222');

INSERT INTO listings (id, business_id) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES
  ('aaaa0000-0000-0000-0000-000000000001', '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'A-Small', 'dog', 'small', 4, 80, 100),
  ('bbbb0000-0000-0000-0000-000000000001', '22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'B-Small', 'dog', 'small', 4, 80, 100);

-- Create an owner + pet
INSERT INTO auth.users (id, email) VALUES ('33333333-3333-3333-3333-333333333333', 'owner@test');
INSERT INTO user_profiles (id, display_name) VALUES ('33333333-3333-3333-3333-333333333333', 'Owner');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333', 'Mochi', 'dog');

-- Booking at Biz A only
INSERT INTO bookings (
  id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '33333333-3333-3333-3333-333333333333',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaa0000-0000-0000-0000-000000000001',
  '2026-05-01', '2026-05-03', 2, 160, 'confirmed'
);

-- Switch to Alice (Biz A admin)
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM bookings), 1, 'Alice sees Biz A booking');

-- Switch to Bob (Biz B admin)
RESET role;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM bookings), 0, 'Bob sees 0 bookings (Biz B has none)');

-- Bob cannot read Biz A by id either
SELECT is((SELECT count(*)::int FROM bookings WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0,
  'Bob cannot see Biz A booking by direct filter');

-- Owner can see their own booking
RESET role;
SET LOCAL request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
SET LOCAL role = 'authenticated';
SELECT is((SELECT count(*)::int FROM bookings), 1, 'Owner sees own booking');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run and expect pass**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```
Expected: all 4 RLS assertions pass. If any fail, the RLS policies in Task 8 have a gap — go fix before moving on.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/002_rls.sql
git commit -m "test(db): RLS blocks cross-business reads"
```

---

## Task 11: Helper functions

Shared utilities used by state-transition functions: compute nights, compute subtotal with peak/off-peak per night, check active vaccination cert exists, check availability.

**Files:**
- Create: `supabase/migrations/009_helper_functions.sql`
- Create: `supabase/tests/003_helper_functions.sql`

- [ ] **Step 1: Write failing helper test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/003_helper_functions.sql`:
```sql
BEGIN;
SELECT plan(5);

-- Seed: a kennel with base RM80, peak RM100
INSERT INTO auth.users (id, email) VALUES ('aaaaaaaa-1111-1111-1111-111111111111','setup@t');
INSERT INTO user_profiles (id, display_name) VALUES ('aaaaaaaa-1111-1111-1111-111111111111','Setup');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('11111111-2222-3333-4444-555555555555','Setup Biz','setup-biz','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('11111111-2222-3333-4444-555555555555','aaaaaaaa-1111-1111-1111-111111111111');
INSERT INTO listings (id, business_id) VALUES
  ('11111111-2222-3333-4444-666666666666','11111111-2222-3333-4444-555555555555');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES ('11111111-2222-3333-4444-777777777777','11111111-2222-3333-4444-666666666666',
        'Small','dog','small',4,80,100);

-- Seed peak calendar: 2026-05-02 is peak (global)
INSERT INTO peak_calendar (date, label) VALUES ('2026-05-02', 'Test weekend');

-- compute_stay_subtotal returns numeric
SELECT has_function('public', 'compute_stay_subtotal', ARRAY['uuid','date','date']);

-- 2 nights, one off-peak, one peak => 80 + 100 = 180
SELECT is(compute_stay_subtotal(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-05-01'::date, '2026-05-03'::date),
  180::numeric, '2 nights, 1 off-peak + 1 peak = 180');

-- 1 night, off-peak => 80
SELECT is(compute_stay_subtotal(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-05-01'::date, '2026-05-02'::date),
  80::numeric, '1 night off-peak = 80');

-- kennel_available checks capacity - (confirmed+pending) >= 1
SELECT has_function('public', 'kennel_available', ARRAY['uuid','date','date','integer']);

-- Empty kennel: capacity 4, needed 1 => available
SELECT ok(kennel_available(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-05-01'::date, '2026-05-03'::date, 1),
  'empty kennel is available');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```
Expected: test 003 fails with "function compute_stay_subtotal does not exist".

- [ ] **Step 3: Write helper-functions migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/009_helper_functions.sql`:
```sql
-- Is a date peak for this business? Platform peak_calendar row (business_id=NULL)
-- OR a business-specific override row counts.
CREATE OR REPLACE FUNCTION is_peak_date(p_business_id uuid, p_date date)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM peak_calendar
    WHERE date = p_date
      AND (business_id IS NULL OR business_id = p_business_id)
  );
$$;

-- Compute subtotal for a stay. Sums per-night prices based on peak/off-peak.
-- check_out is exclusive (same semantics as bookings.nights).
CREATE OR REPLACE FUNCTION compute_stay_subtotal(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date
) RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_biz uuid;
  v_base numeric;
  v_peak numeric;
  v_total numeric := 0;
  v_d date := p_check_in;
BEGIN
  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  SELECT l.business_id, kt.base_price_myr, kt.peak_price_myr
    INTO v_biz, v_base, v_peak
    FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
    WHERE kt.id = p_kennel_type_id;

  IF v_biz IS NULL THEN
    RAISE EXCEPTION 'kennel_type_id % not found', p_kennel_type_id;
  END IF;

  WHILE v_d < p_check_out LOOP
    v_total := v_total + CASE WHEN is_peak_date(v_biz, v_d) THEN v_peak ELSE v_base END;
    v_d := v_d + 1;
  END LOOP;

  RETURN v_total;
END;
$$;

-- How many of a kennel type are occupied on any day in [check_in, check_out)?
-- Considers bookings in active states (accepted, pending_payment, confirmed) and manual blocks.
CREATE OR REPLACE FUNCTION kennel_occupied_count(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date
) RETURNS integer
LANGUAGE sql STABLE
AS $$
  WITH day_range AS (
    SELECT generate_series(p_check_in, p_check_out - 1, '1 day'::interval)::date AS d
  ),
  occupied AS (
    SELECT d, (
      SELECT count(*)::int FROM bookings b
      WHERE b.kennel_type_id = p_kennel_type_id
        AND b.status IN ('accepted','pending_payment','confirmed')
        AND d >= b.check_in AND d < b.check_out
    ) + (
      SELECT count(*)::int FROM availability_overrides ao
      WHERE ao.kennel_type_id = p_kennel_type_id
        AND ao.date = d AND ao.manual_block
    ) AS cnt
    FROM day_range
  )
  SELECT COALESCE(max(cnt), 0) FROM occupied;
$$;

-- Is at least p_needed units of the kennel available throughout [check_in, check_out)?
CREATE OR REPLACE FUNCTION kennel_available(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date,
  p_needed integer
) RETURNS boolean
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_cap integer;
  v_occ integer;
BEGIN
  SELECT capacity INTO v_cap FROM kennel_types WHERE id = p_kennel_type_id AND active;
  IF v_cap IS NULL THEN RETURN false; END IF;
  v_occ := kennel_occupied_count(p_kennel_type_id, p_check_in, p_check_out);
  RETURN (v_cap - v_occ) >= p_needed;
END;
$$;

-- Does this pet have a cert valid for the whole stay?
CREATE OR REPLACE FUNCTION pet_has_valid_cert(
  p_pet_id uuid,
  p_check_out date
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vaccination_certs
    WHERE pet_id = p_pet_id AND expires_on >= p_check_out
  );
$$;
```

- [ ] **Step 4: Apply + re-run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```
Expected: all tests pass, including the 5 helper-function assertions.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/009_helper_functions.sql supabase/tests/003_helper_functions.sql
git commit -m "feat(db): helper functions for pricing and availability"
```

---

## Task 12: State transition — `create_booking_request` (request-to-book path)

Spec §7. Creates a booking in state `requested` with a 24h acceptance deadline. Preconditions: pet belongs to owner, kennel is available, pet has valid cert, kennel is NOT instant-book.

**Files:**
- Modify: `supabase/migrations/010_state_transitions.sql` (created this task)
- Create: `supabase/tests/004_booking_request.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/004_booking_request.sql`:
```sql
BEGIN;
SELECT plan(6);

-- Seed: owner, pet, cert, business, listing, kennel
INSERT INTO auth.users (id, email) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','owner@t'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admin@t');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Owner','owner'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Admin','business_admin');

INSERT INTO pets (id, owner_id, name, species) VALUES
  ('33333333-cccc-cccc-cccc-cccccccccccc','11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Mochi','dog');

-- Cert valid until 2027
INSERT INTO vaccination_certs (pet_id, file_url, vaccines_covered, issued_on, expires_on)
VALUES ('33333333-cccc-cccc-cccc-cccccccccccc','https://x','{rabies}','2025-01-01','2027-01-01');

INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('44444444-dddd-dddd-dddd-dddddddddddd','Biz','biz','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('44444444-dddd-dddd-dddd-dddddddddddd','22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
INSERT INTO listings (id, business_id) VALUES
  ('55555555-eeee-eeee-eeee-eeeeeeeeeeee','44444444-dddd-dddd-dddd-dddddddddddd');

-- Non-instant-book kennel
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('66666666-ffff-ffff-ffff-ffffffffffff','55555555-eeee-eeee-eeee-eeeeeeeeeeee',
        'Small','dog','small',2,80,100,false);

-- Impersonate owner
SET LOCAL request.jwt.claim.sub = '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET LOCAL role = 'authenticated';

-- Happy path
SELECT has_function('public', 'create_booking_request', ARRAY['uuid','uuid[]','date','date','text']);

DO $$
DECLARE v_booking_id uuid;
BEGIN
  v_booking_id := create_booking_request(
    '66666666-ffff-ffff-ffff-ffffffffffff'::uuid,
    ARRAY['33333333-cccc-cccc-cccc-cccccccccccc'::uuid],
    '2026-05-01'::date, '2026-05-03'::date,
    'Test notes'
  );
  PERFORM set_config('petbnb.test_booking_id', v_booking_id::text, true);
END $$;

SELECT is(
  (SELECT status FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  'requested'::booking_status,
  'new booking is requested');

SELECT is(
  (SELECT nights FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  2, 'nights = 2');

SELECT is(
  (SELECT subtotal_myr FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  160::numeric, 'subtotal = 2 * 80 = 160');

-- Cert snapshot created
SELECT is(
  (SELECT count(*)::int FROM booking_cert_snapshots
     WHERE booking_id = current_setting('petbnb.test_booking_id')::uuid),
  1, 'one cert snapshotted');

-- Illegal: instant-book kennel cannot go through request path
UPDATE kennel_types SET instant_book = true WHERE id = '66666666-ffff-ffff-ffff-ffffffffffff';
SELECT throws_like(
  $ct$ SELECT create_booking_request(
    '66666666-ffff-ffff-ffff-ffffffffffff'::uuid,
    ARRAY['33333333-cccc-cccc-cccc-cccccccccccc'::uuid],
    '2026-06-01'::date, '2026-06-02'::date, NULL)
  $ct$,
  '%instant_book%',
  'cannot request-to-book an instant-book kennel'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```
Expected: `function create_booking_request does not exist`.

- [ ] **Step 3: Implement**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/010_state_transitions.sql`:
```sql
-- create_booking_request: request-to-book path.
-- Preconditions:
--   - caller owns every pet in p_pet_ids
--   - kennel is active and NOT instant_book
--   - each pet has a vaccination cert valid through check_out
--   - capacity - current occupancy - manual blocks >= 1 across [check_in, check_out)
-- Effect: inserts booking with status='requested', acceptance deadline = now()+24h.
CREATE OR REPLACE FUNCTION create_booking_request(
  p_kennel_type_id uuid,
  p_pet_ids uuid[],
  p_check_in date,
  p_check_out date,
  p_special_instructions text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_kennel kennel_types%ROWTYPE;
  v_business_id uuid;
  v_listing_id uuid;
  v_nights integer;
  v_subtotal numeric;
  v_platform_fee numeric;
  v_booking_id uuid;
  v_pet_id uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is null; must be called by an authenticated user';
  END IF;

  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  IF array_length(p_pet_ids, 1) IS NULL OR array_length(p_pet_ids, 1) = 0 THEN
    RAISE EXCEPTION 'at least one pet required';
  END IF;

  -- Lock the kennel row for the duration of the tx so racing requests serialize
  SELECT * INTO v_kennel FROM kennel_types WHERE id = p_kennel_type_id AND active FOR UPDATE;
  IF v_kennel IS NULL THEN
    RAISE EXCEPTION 'kennel_type % is not active or not found', p_kennel_type_id;
  END IF;

  IF v_kennel.instant_book THEN
    RAISE EXCEPTION 'kennel is instant_book; use create_instant_booking instead';
  END IF;

  SELECT l.id, l.business_id INTO v_listing_id, v_business_id
    FROM listings l WHERE l.id = v_kennel.listing_id;

  -- Every pet must belong to the caller
  FOREACH v_pet_id IN ARRAY p_pet_ids LOOP
    PERFORM 1 FROM pets WHERE id = v_pet_id AND owner_id = v_owner_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'pet % does not belong to caller', v_pet_id;
    END IF;
    IF NOT pet_has_valid_cert(v_pet_id, p_check_out) THEN
      RAISE EXCEPTION 'pet % has no valid vaccination cert for this stay', v_pet_id
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  IF NOT kennel_available(p_kennel_type_id, p_check_in, p_check_out, 1) THEN
    RAISE EXCEPTION 'kennel_type % not available for % to %', p_kennel_type_id, p_check_in, p_check_out;
  END IF;

  v_nights := (p_check_out - p_check_in);
  v_subtotal := compute_stay_subtotal(p_kennel_type_id, p_check_in, p_check_out);

  -- Commission: resolved from business.commission_rate_bps (defaults to 1200 = 12%)
  v_platform_fee := round(v_subtotal * (
    (SELECT commission_rate_bps FROM businesses WHERE id = v_business_id) / 10000.0
  ), 2);

  INSERT INTO bookings (
    owner_id, business_id, listing_id, kennel_type_id,
    check_in, check_out, nights,
    subtotal_myr, platform_fee_myr, business_payout_myr,
    status, special_instructions, payment_deadline
  )
  VALUES (
    v_owner_id, v_business_id, v_listing_id, p_kennel_type_id,
    p_check_in, p_check_out, v_nights,
    v_subtotal, v_platform_fee, v_subtotal - v_platform_fee,
    'requested', p_special_instructions, now() + interval '24 hours'
  )
  RETURNING id INTO v_booking_id;

  -- booking_pets
  INSERT INTO booking_pets (booking_id, pet_id)
  SELECT v_booking_id, unnest(p_pet_ids);

  -- Cert snapshots (latest cert per pet)
  INSERT INTO booking_cert_snapshots (booking_id, pet_id, vaccination_cert_id, file_url, expires_on)
  SELECT v_booking_id, vc.pet_id, vc.id, vc.file_url, vc.expires_on
  FROM vaccination_certs vc
  WHERE vc.pet_id = ANY(p_pet_ids)
    AND vc.id = (
      SELECT id FROM vaccination_certs vc2
      WHERE vc2.pet_id = vc.pet_id
      ORDER BY expires_on DESC LIMIT 1
    );

  -- Notify owner + business admins
  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_owner_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id));

  INSERT INTO notifications (user_id, kind, payload)
  SELECT bm.user_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id)
  FROM business_members bm WHERE bm.business_id = v_business_id;

  RETURN v_booking_id;
END;
$$;
```

- [ ] **Step 4: Apply + re-run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/010_state_transitions.sql supabase/tests/004_booking_request.sql
git commit -m "feat(db): create_booking_request state transition"
```

---

## Task 13: State transitions — `accept_booking` and `decline_booking`

Business_admin transitions a `requested` booking to `accepted` (setting 24h payment deadline) or `declined`.

**Files:**
- Modify: `supabase/migrations/010_state_transitions.sql` (append)
- Create: `supabase/tests/005_booking_accept_decline.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/005_booking_accept_decline.sql`:
```sql
BEGIN;
SELECT plan(6);

-- Reusable seed: owner, pet+cert, business admin, kennel, requested booking
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1111-0000-0000-0000-000000000001','owner@t'),
  ('bbbb1111-0000-0000-0000-000000000002','admin@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('aaaa1111-0000-0000-0000-000000000001','Owner'),
  ('bbbb1111-0000-0000-0000-000000000002','Admin');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('aaaa1111-0000-0000-0000-00000000p001','aaaa1111-0000-0000-0000-000000000001','M','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on) VALUES
  ('aaaa1111-0000-0000-0000-00000000p001','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('bbbb1111-0000-0000-0000-000000000100','B','b','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('bbbb1111-0000-0000-0000-000000000100','bbbb1111-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('bbbb1111-0000-0000-0000-000000000200','bbbb1111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES ('bbbb1111-0000-0000-0000-000000000300','bbbb1111-0000-0000-0000-000000000200',
        'K','dog','small',2,80,100);

-- Owner creates request
SET LOCAL request.jwt.claim.sub = 'aaaa1111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_booking_request(
    'bbbb1111-0000-0000-0000-000000000300'::uuid,
    ARRAY['aaaa1111-0000-0000-0000-00000000p001'::uuid],
    '2026-06-01'::date, '2026-06-03'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

-- Admin accepts
RESET role;
SET LOCAL request.jwt.claim.sub = 'bbbb1111-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT has_function('public','accept_booking',ARRAY['uuid']);
SELECT lives_ok(
  'SELECT accept_booking((SELECT current_setting(''petbnb.bid'')::uuid))',
  'admin can accept');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'accepted'::booking_status, 'status flipped to accepted');

-- Idempotency check: re-accepting errors
SELECT throws_like(
  'SELECT accept_booking((SELECT current_setting(''petbnb.bid'')::uuid))',
  '%not in requested%',
  'cannot accept twice');

-- Now test decline on a fresh booking
RESET role;
SET LOCAL request.jwt.claim.sub = 'aaaa1111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_booking_request(
    'bbbb1111-0000-0000-0000-000000000300'::uuid,
    ARRAY['aaaa1111-0000-0000-0000-00000000p001'::uuid],
    '2026-07-01'::date, '2026-07-02'::date, NULL);
  PERFORM set_config('petbnb.bid2', v_id::text, true);
END $$;

RESET role;
SET LOCAL request.jwt.claim.sub = 'bbbb1111-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT lives_ok(
  'SELECT decline_booking((SELECT current_setting(''petbnb.bid2'')::uuid))',
  'admin can decline');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid2')::uuid),
  'declined'::booking_status, 'declined recorded');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```
Expected: `function accept_booking does not exist`.

- [ ] **Step 3: Append to 010_state_transitions.sql**

Append to `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/010_state_transitions.sql`:
```sql
-- accept_booking: business_admin transitions requested -> accepted
-- Sets payment_deadline = now() + 24h
CREATE OR REPLACE FUNCTION accept_booking(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id;
  END IF;
  IF NOT is_business_member(v_row.business_id) THEN
    RAISE EXCEPTION 'not a member of owning business';
  END IF;
  IF v_row.status != 'requested' THEN
    RAISE EXCEPTION 'booking % not in requested state (is %)', p_booking_id, v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'accepted',
    acted_at = now(),
    payment_deadline = now() + interval '24 hours'
  WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'request_accepted', jsonb_build_object('booking_id', p_booking_id));
END;
$$;

-- decline_booking: business_admin transitions requested -> declined
CREATE OR REPLACE FUNCTION decline_booking(p_booking_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id;
  END IF;
  IF NOT is_business_member(v_row.business_id) THEN
    RAISE EXCEPTION 'not a member of owning business';
  END IF;
  IF v_row.status != 'requested' THEN
    RAISE EXCEPTION 'booking % not in requested state (is %)', p_booking_id, v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'declined',
    acted_at = now(),
    special_instructions = COALESCE(special_instructions, '') ||
      CASE WHEN p_reason IS NOT NULL THEN E'\n[decline reason] ' || p_reason ELSE '' END
  WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'request_declined', jsonb_build_object('booking_id', p_booking_id, 'reason', p_reason));
END;
$$;
```

- [ ] **Step 4: Apply + re-run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```
Expected: all 004 and 005 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/010_state_transitions.sql supabase/tests/005_booking_accept_decline.sql
git commit -m "feat(db): accept_booking and decline_booking transitions"
```

---

## Task 14: `create_instant_booking`

Instant-book path. Same preconditions as `create_booking_request` except the kennel must BE `instant_book`, and the resulting status is `pending_payment` with a 15-minute deadline.

**Files:**
- Modify: `supabase/migrations/010_state_transitions.sql` (append)
- Create: `supabase/tests/006_booking_instant.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/006_booking_instant.sql`:
```sql
BEGIN;
SELECT plan(4);

-- Seed similar to 005 but kennel is instant_book
INSERT INTO auth.users (id, email) VALUES ('a6661111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a6661111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a6661111-0000-0000-0000-00000000p001','a6661111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a6661111-0000-0000-0000-00000000p001','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b6661111-0000-0000-0000-000000000100','B','bi','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b6661111-0000-0000-0000-000000000200','b6661111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b6661111-0000-0000-0000-000000000300','b6661111-0000-0000-0000-000000000200',
        'K','dog','small',1,80,100,true);

SET LOCAL request.jwt.claim.sub = 'a6661111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT has_function('public','create_instant_booking',ARRAY['uuid','uuid[]','date','date','text']);

DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_instant_booking(
    'b6661111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a6661111-0000-0000-0000-00000000p001'::uuid],
    '2026-08-01'::date, '2026-08-02'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'pending_payment'::booking_status, 'instant booking goes straight to pending_payment');

SELECT ok(
  (SELECT payment_deadline FROM bookings WHERE id = current_setting('petbnb.bid')::uuid)
  BETWEEN now() + interval '10 minutes' AND now() + interval '20 minutes',
  'payment_deadline is ~15 min away');

-- Capacity is 1; a second instant booking for overlapping days should fail
SELECT throws_like(
  'SELECT create_instant_booking(
     ''b6661111-0000-0000-0000-000000000300''::uuid,
     ARRAY[''a6661111-0000-0000-0000-00000000p001''::uuid],
     ''2026-08-01''::date, ''2026-08-02''::date, NULL)',
  '%not available%',
  'overlapping instant booking fails');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```

- [ ] **Step 3: Append to 010_state_transitions.sql**

Append:
```sql
CREATE OR REPLACE FUNCTION create_instant_booking(
  p_kennel_type_id uuid,
  p_pet_ids uuid[],
  p_check_in date,
  p_check_out date,
  p_special_instructions text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_kennel kennel_types%ROWTYPE;
  v_business_id uuid;
  v_listing_id uuid;
  v_nights integer;
  v_subtotal numeric;
  v_platform_fee numeric;
  v_booking_id uuid;
  v_pet_id uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is null';
  END IF;

  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  IF array_length(p_pet_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'at least one pet required';
  END IF;

  SELECT * INTO v_kennel FROM kennel_types WHERE id = p_kennel_type_id AND active FOR UPDATE;
  IF v_kennel IS NULL THEN
    RAISE EXCEPTION 'kennel_type % not active/found', p_kennel_type_id;
  END IF;

  IF NOT v_kennel.instant_book THEN
    RAISE EXCEPTION 'kennel is not instant_book; use create_booking_request';
  END IF;

  SELECT l.id, l.business_id INTO v_listing_id, v_business_id
    FROM listings l WHERE l.id = v_kennel.listing_id;

  FOREACH v_pet_id IN ARRAY p_pet_ids LOOP
    PERFORM 1 FROM pets WHERE id = v_pet_id AND owner_id = v_owner_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'pet % not owned by caller', v_pet_id; END IF;
    IF NOT pet_has_valid_cert(v_pet_id, p_check_out) THEN
      RAISE EXCEPTION 'pet % has no valid cert', v_pet_id USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  IF NOT kennel_available(p_kennel_type_id, p_check_in, p_check_out, 1) THEN
    RAISE EXCEPTION 'kennel not available for %..%', p_check_in, p_check_out;
  END IF;

  v_nights := (p_check_out - p_check_in);
  v_subtotal := compute_stay_subtotal(p_kennel_type_id, p_check_in, p_check_out);
  v_platform_fee := round(v_subtotal * (
    (SELECT commission_rate_bps FROM businesses WHERE id = v_business_id) / 10000.0
  ), 2);

  INSERT INTO bookings (
    owner_id, business_id, listing_id, kennel_type_id,
    check_in, check_out, nights,
    subtotal_myr, platform_fee_myr, business_payout_myr,
    status, special_instructions, payment_deadline, acted_at
  )
  VALUES (
    v_owner_id, v_business_id, v_listing_id, p_kennel_type_id,
    p_check_in, p_check_out, v_nights,
    v_subtotal, v_platform_fee, v_subtotal - v_platform_fee,
    'pending_payment', p_special_instructions,
    now() + interval '15 minutes', now()
  )
  RETURNING id INTO v_booking_id;

  INSERT INTO booking_pets (booking_id, pet_id)
  SELECT v_booking_id, unnest(p_pet_ids);

  INSERT INTO booking_cert_snapshots (booking_id, pet_id, vaccination_cert_id, file_url, expires_on)
  SELECT v_booking_id, vc.pet_id, vc.id, vc.file_url, vc.expires_on
  FROM vaccination_certs vc
  WHERE vc.pet_id = ANY(p_pet_ids)
    AND vc.id = (SELECT id FROM vaccination_certs WHERE pet_id = vc.pet_id
                 ORDER BY expires_on DESC LIMIT 1);

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_owner_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id, 'instant', true));

  RETURN v_booking_id;
END;
$$;
```

- [ ] **Step 4: Apply + test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/010_state_transitions.sql supabase/tests/006_booking_instant.sql
git commit -m "feat(db): create_instant_booking transition"
```

---

## Task 15: Payment transitions — `create_payment_intent` + `confirm_payment`

`create_payment_intent` validates the booking is in `accepted` or `pending_payment` and owned by caller, returns a generated iPay88 reference. `confirm_payment` (called by the webhook Edge Function, with `SECURITY DEFINER` and a service-role RPC) transitions to `confirmed`.

**Files:**
- Modify: `supabase/migrations/010_state_transitions.sql` (append)
- Create: `supabase/tests/007_booking_payment.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/007_booking_payment.sql`:
```sql
BEGIN;
SELECT plan(6);

-- Seed from 005 re-used (minimal here for brevity)
INSERT INTO auth.users (id, email) VALUES ('a7771111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a7771111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a7771111-0000-0000-0000-00000000p001','a7771111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a7771111-0000-0000-0000-00000000p001','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b7771111-0000-0000-0000-000000000100','B','bj','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b7771111-0000-0000-0000-000000000200','b7771111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b7771111-0000-0000-0000-000000000300','b7771111-0000-0000-0000-000000000200',
        'K','dog','small',1,80,100,true);

SET LOCAL request.jwt.claim.sub = 'a7771111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Create a pending_payment via instant-book
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_instant_booking(
    'b7771111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a7771111-0000-0000-0000-00000000p001'::uuid],
    '2026-09-01'::date, '2026-09-03'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

SELECT has_function('public','create_payment_intent',ARRAY['uuid']);

DO $$
DECLARE v_ref text;
BEGIN
  v_ref := create_payment_intent(current_setting('petbnb.bid')::uuid);
  PERFORM set_config('petbnb.ref', v_ref, true);
END $$;

SELECT isnt((SELECT current_setting('petbnb.ref')), NULL, 'ref_no returned');

SELECT is((SELECT ipay88_reference FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  current_setting('petbnb.ref'), 'ref stored on booking');

-- confirm_payment flips to confirmed and is idempotent
-- Run as service_role (bypasses RLS check but SECURITY DEFINER function still checks state)
RESET role;

SELECT has_function('public','confirm_payment',ARRAY['text','numeric']);

SELECT lives_ok(
  format('SELECT confirm_payment(%L, 160::numeric)', current_setting('petbnb.ref')),
  'first confirm_payment succeeds');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'confirmed'::booking_status, 'booking is confirmed');

-- Idempotency: second call is a no-op, does not error
SELECT lives_ok(
  format('SELECT confirm_payment(%L, 160::numeric)', current_setting('petbnb.ref')),
  'second confirm_payment is idempotent (no error)');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```

- [ ] **Step 3: Append to 010_state_transitions.sql**

```sql
-- create_payment_intent: caller (owner) gets a ref_no for the booking.
-- Booking must be in 'accepted' or 'pending_payment'. Freezes the amount.
CREATE OR REPLACE FUNCTION create_payment_intent(p_booking_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
  v_ref text;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN RAISE EXCEPTION 'booking not found'; END IF;
  IF v_row.owner_id != auth.uid() THEN
    RAISE EXCEPTION 'only booking owner can create payment intent';
  END IF;
  IF v_row.status NOT IN ('accepted','pending_payment') THEN
    RAISE EXCEPTION 'booking % not payable (is %)', p_booking_id, v_row.status;
  END IF;
  IF v_row.payment_deadline < now() THEN
    RAISE EXCEPTION 'payment deadline passed';
  END IF;

  -- If a ref was already issued, return it (idempotent)
  IF v_row.ipay88_reference IS NOT NULL THEN
    RETURN v_row.ipay88_reference;
  END IF;

  -- Ref format: PETBNB-<8-char uid>-<booking short>
  v_ref := 'PETBNB-' || substr(replace(gen_random_uuid()::text,'-',''),1,8) || '-'
           || substr(p_booking_id::text, 1, 8);

  -- If booking was 'accepted', transition to 'pending_payment'
  UPDATE bookings SET
    ipay88_reference = v_ref,
    status = CASE WHEN status = 'accepted' THEN 'pending_payment'::booking_status ELSE status END
  WHERE id = p_booking_id;

  RETURN v_ref;
END;
$$;

-- confirm_payment: called by the iPay88 webhook Edge Function.
-- Idempotent by ref_no. Only transitions pending_payment -> confirmed.
-- Takes received_amount so we can detect tampering (iPay88 tells us what was charged).
CREATE OR REPLACE FUNCTION confirm_payment(p_ref text, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE ipay88_reference = p_ref FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'no booking with reference %', p_ref;
  END IF;

  -- Idempotent: already confirmed, do nothing
  IF v_row.status = 'confirmed' THEN
    RETURN;
  END IF;

  IF v_row.status != 'pending_payment' THEN
    RAISE EXCEPTION 'booking for ref % not in pending_payment (is %)', p_ref, v_row.status;
  END IF;

  -- Amount must match subtotal to the cent
  IF abs(p_amount - v_row.subtotal_myr) > 0.01 THEN
    RAISE EXCEPTION 'amount mismatch: expected %, got %', v_row.subtotal_myr, p_amount;
  END IF;

  UPDATE bookings SET
    status = 'confirmed',
    acted_at = now()
  WHERE id = v_row.id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'payment_confirmed', jsonb_build_object('booking_id', v_row.id, 'ref', p_ref));

  INSERT INTO notifications (user_id, kind, payload)
  SELECT bm.user_id, 'payment_confirmed', jsonb_build_object('booking_id', v_row.id, 'ref', p_ref)
  FROM business_members bm WHERE bm.business_id = v_row.business_id;
END;
$$;
```

- [ ] **Step 4: Apply + test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```
Expected: all 007 assertions pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/010_state_transitions.sql supabase/tests/007_booking_payment.sql
git commit -m "feat(db): create_payment_intent and confirm_payment transitions"
```

---

## Task 16: Cancellation transitions

`cancel_booking_by_owner` and `cancel_booking_by_business`. Both only valid from `confirmed`. Owner cancellation respects listing's cancellation_policy preset (Phase 0 does NOT compute refund amount — that's Phase 3/5; this just records state transition and reason).

**Files:**
- Modify: `supabase/migrations/010_state_transitions.sql` (append)
- Create: `supabase/tests/008_booking_cancel.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/008_booking_cancel.sql`:
```sql
BEGIN;
SELECT plan(5);

INSERT INTO auth.users (id, email) VALUES
  ('a8881111-0000-0000-0000-000000000001','o@t'),
  ('b8881111-0000-0000-0000-000000000002','adm@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('a8881111-0000-0000-0000-000000000001','O'),
  ('b8881111-0000-0000-0000-000000000002','Adm');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a8881111-0000-0000-0000-00000000p001','a8881111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a8881111-0000-0000-0000-00000000p001','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b8881111-0000-0000-0000-000000000100','B','bk','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('b8881111-0000-0000-0000-000000000100','b8881111-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('b8881111-0000-0000-0000-000000000200','b8881111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b8881111-0000-0000-0000-000000000300','b8881111-0000-0000-0000-000000000200','K','dog','small',2,80,100,true);

-- Owner creates + pays (via helpers) -> confirmed
SET LOCAL request.jwt.claim.sub = 'a8881111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid; v_ref text;
BEGIN
  v_id := create_instant_booking(
    'b8881111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a8881111-0000-0000-0000-00000000p001'::uuid],
    '2026-10-01'::date, '2026-10-03'::date, NULL);
  v_ref := create_payment_intent(v_id);
  PERFORM set_config('petbnb.bid', v_id::text, true);
  PERFORM set_config('petbnb.ref', v_ref, true);
END $$;
RESET role;
SELECT confirm_payment(current_setting('petbnb.ref'), 160::numeric);

-- Owner cancels
SET LOCAL request.jwt.claim.sub = 'a8881111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT has_function('public','cancel_booking_by_owner',ARRAY['uuid']);
SELECT lives_ok(
  'SELECT cancel_booking_by_owner((SELECT current_setting(''petbnb.bid'')::uuid))',
  'owner cancels confirmed booking');
SELECT is(
  (SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'cancelled_by_owner'::booking_status, 'status=cancelled_by_owner');

-- Cancelling again errors
SELECT throws_like(
  'SELECT cancel_booking_by_owner((SELECT current_setting(''petbnb.bid'')::uuid))',
  '%not confirmed%',
  'cannot cancel twice');

SELECT has_function('public','cancel_booking_by_business',ARRAY['uuid','text']);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```

- [ ] **Step 3: Append to 010_state_transitions.sql**

```sql
CREATE OR REPLACE FUNCTION cancel_booking_by_owner(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN RAISE EXCEPTION 'booking not found'; END IF;
  IF v_row.owner_id != auth.uid() THEN RAISE EXCEPTION 'only owner may cancel'; END IF;
  IF v_row.status != 'confirmed' THEN
    RAISE EXCEPTION 'booking not confirmed (is %)', v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'cancelled_by_owner',
    terminal_reason = 'owner_cancelled',
    acted_at = now()
  WHERE id = p_booking_id;

  -- Refund calculation deferred to Phase 3/5
  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'booking_cancelled', jsonb_build_object('booking_id', p_booking_id, 'by','owner'));
  INSERT INTO notifications (user_id, kind, payload)
  SELECT bm.user_id, 'booking_cancelled', jsonb_build_object('booking_id', p_booking_id, 'by','owner')
  FROM business_members bm WHERE bm.business_id = v_row.business_id;
END;
$$;

CREATE OR REPLACE FUNCTION cancel_booking_by_business(p_booking_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN RAISE EXCEPTION 'booking not found'; END IF;
  IF NOT is_business_member(v_row.business_id) THEN
    RAISE EXCEPTION 'not a member of owning business';
  END IF;
  IF v_row.status != 'confirmed' THEN
    RAISE EXCEPTION 'booking not confirmed (is %)', v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'cancelled_by_business',
    terminal_reason = 'business_cancelled',
    acted_at = now(),
    special_instructions = COALESCE(special_instructions, '') ||
      E'\n[cancellation by business] ' || COALESCE(p_reason, 'no reason given')
  WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'booking_cancelled',
    jsonb_build_object('booking_id', p_booking_id, 'by','business','reason', p_reason));
END;
$$;
```

- [ ] **Step 4: Apply + test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/010_state_transitions.sql supabase/tests/008_booking_cancel.sql
git commit -m "feat(db): owner and business cancellation transitions"
```

---

## Task 17: Scheduled sweeps + pg_cron schedules

Spec §7 Implementation. Three sweep functions + one stub:

1. `sweep_expire_stale_requests()` — requested past 24h -> expired
2. `sweep_expire_stale_payments()` — accepted/pending_payment past deadline -> expired
3. `sweep_complete_past_bookings()` — confirmed + check_out < today -> completed + review_prompt notification
4. `sweep_reconcile_pending_payments()` — stub; Phase 3 wires iPay88 lookup

Then schedule via `pg_cron`.

**Files:**
- Create: `supabase/migrations/011_scheduled_sweeps.sql`
- Create: `supabase/tests/009_sweeps.sql`

- [ ] **Step 1: Write failing tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/009_sweeps.sql`:
```sql
BEGIN;
SELECT plan(5);

-- Seed a business + kennel + owner with insertable requested + confirmed rows
INSERT INTO auth.users (id, email) VALUES ('a9991111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a9991111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a9991111-0000-0000-0000-00000000p001','a9991111-0000-0000-0000-000000000001','X','dog');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b9991111-0000-0000-0000-000000000100','B','bl','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b9991111-0000-0000-0000-000000000200','b9991111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b9991111-0000-0000-0000-000000000300','b9991111-0000-0000-0000-000000000200','K','dog','small',3,80,100,false);

-- Insert a stale 'requested' (older than 24h) directly
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000001',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-01-01','2027-01-02',1,80,'requested', now()-interval '25 hours', NULL);

-- Insert a fresh 'requested' (within window) -> should NOT expire
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000002',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-02-01','2027-02-02',1,80,'requested', now()-interval '1 hour', NULL);

-- Insert a stale pending_payment (past deadline)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000003',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-03-01','2027-03-02',1,80,'pending_payment', now()-interval '1 hour', now()-interval '10 minutes');

-- Insert a past confirmed booking (check_out yesterday)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at)
VALUES ('c1111111-0000-0000-0000-000000000004',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  CURRENT_DATE - interval '5 days', CURRENT_DATE - interval '1 day', 4, 320, 'confirmed', now()-interval '10 days');

SELECT has_function('public','sweep_expire_stale_requests',ARRAY[]::text[]);

SELECT lives_ok('SELECT sweep_expire_stale_requests()', 'stale-request sweep runs');
SELECT is(
  (SELECT status FROM bookings WHERE id = 'c1111111-0000-0000-0000-000000000001'),
  'expired'::booking_status, 'stale requested booking expired');
SELECT is(
  (SELECT status FROM bookings WHERE id = 'c1111111-0000-0000-0000-000000000002'),
  'requested'::booking_status, 'fresh requested booking kept');

SELECT lives_ok('SELECT sweep_expire_stale_payments()', 'payment-expire sweep runs');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run; expect FAIL**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase test db
```

- [ ] **Step 3: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/011_scheduled_sweeps.sql`:
```sql
-- Expire requested bookings older than 24h
CREATE OR REPLACE FUNCTION sweep_expire_stale_requests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE bookings SET
      status = 'expired',
      terminal_reason = 'no_response_24h',
      acted_at = now()
    WHERE status = 'requested'
      AND requested_at < now() - interval '24 hours'
    RETURNING id, owner_id
  )
  SELECT count(*) INTO v_count FROM expired;

  INSERT INTO notifications (user_id, kind, payload)
  SELECT owner_id, 'booking_cancelled', jsonb_build_object('booking_id', id, 'reason','request_timed_out')
  FROM bookings WHERE status = 'expired' AND terminal_reason = 'no_response_24h'
    AND acted_at > now() - interval '1 minute';

  RETURN v_count;
END;
$$;

-- Expire accepted/pending_payment bookings past their payment_deadline
CREATE OR REPLACE FUNCTION sweep_expire_stale_payments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  UPDATE bookings SET
    status = 'expired',
    terminal_reason = CASE
      WHEN status = 'pending_payment' AND payment_deadline <= requested_at + interval '20 minutes'
        THEN 'no_payment_15min_instant'
      ELSE 'no_payment_24h'
    END,
    acted_at = now()
  WHERE status IN ('accepted','pending_payment')
    AND payment_deadline < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Complete bookings whose check_out is in the past
CREATE OR REPLACE FUNCTION sweep_complete_past_bookings()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  WITH done AS (
    UPDATE bookings SET
      status = 'completed',
      acted_at = now()
    WHERE status = 'confirmed'
      AND check_out < CURRENT_DATE
    RETURNING id, owner_id
  )
  SELECT count(*) INTO v_count FROM done;

  INSERT INTO notifications (user_id, kind, payload)
  SELECT owner_id, 'review_prompt', jsonb_build_object('booking_id', id)
  FROM bookings WHERE status = 'completed' AND acted_at > now() - interval '1 minute';

  RETURN v_count;
END;
$$;

-- Phase 0 stub: Phase 3 wires iPay88 lookup API.
CREATE OR REPLACE FUNCTION sweep_reconcile_pending_payments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Intentionally empty in Phase 0. Phase 3: call iPay88 lookup for each
  -- pending_payment >20m old, compare with their record, reconcile.
  RETURN 0;
END;
$$;

-- Schedule via pg_cron (all times in UTC; Supabase pg_cron uses UTC)
-- Only schedule if pg_cron extension is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedule any existing PetBnB jobs first (idempotent re-apply)
    PERFORM cron.unschedule(jobid) FROM cron.job
      WHERE jobname IN (
        'petbnb_expire_requests','petbnb_expire_payments',
        'petbnb_complete_past','petbnb_reconcile_payments'
      );

    PERFORM cron.schedule('petbnb_expire_requests',  '*/5 * * * *',  'SELECT sweep_expire_stale_requests();');
    PERFORM cron.schedule('petbnb_expire_payments',  '*/5 * * * *',  'SELECT sweep_expire_stale_payments();');
    PERFORM cron.schedule('petbnb_complete_past',    '5 16 * * *',   'SELECT sweep_complete_past_bookings();'); -- 00:05 MY = 16:05 UTC
    PERFORM cron.schedule('petbnb_reconcile_payments','*/30 * * * *','SELECT sweep_reconcile_pending_payments();');
  END IF;
END $$;
```

- [ ] **Step 4: Apply + test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
supabase test db
```
Expected: all 009 assertions pass.

- [ ] **Step 5: Verify cron jobs scheduled**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT jobname, schedule FROM cron.job WHERE jobname LIKE 'petbnb_%';"
```
Expected: 4 jobs listed.

- [ ] **Step 6: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/011_scheduled_sweeps.sql supabase/tests/009_sweeps.sql
git commit -m "feat(db): scheduled sweeps and pg_cron wiring"
```

---

## Task 18: Seed peak calendar (MY public + school holidays 2026–2027)

Spec §3 O5. Platform-wide peak dates. These are MY federal public holidays + school holiday windows for 2026 and 2027.

**Files:**
- Create: `supabase/migrations/012_seed_peak_calendar.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/012_seed_peak_calendar.sql`. Dates from official MY calendars:
```sql
-- MY public holidays (federal) + school holidays — platform-wide peak rows.
-- Re-runnable: ON CONFLICT skips existing.
INSERT INTO peak_calendar (date, label) VALUES
  -- 2026 public holidays
  ('2026-01-01','New Year'),
  ('2026-01-28','Thaipusam'),
  ('2026-02-17','Chinese New Year'),
  ('2026-02-18','Chinese New Year'),
  ('2026-03-21','Hari Raya Aidilfitri'),
  ('2026-03-22','Hari Raya Aidilfitri'),
  ('2026-05-01','Labour Day'),
  ('2026-05-21','Wesak'),
  ('2026-05-28','Hari Raya Haji'),
  ('2026-06-06','Agong Birthday'),
  ('2026-06-17','Awal Muharram'),
  ('2026-08-26','Maulidur Rasul'),
  ('2026-08-31','National Day'),
  ('2026-09-16','Malaysia Day'),
  ('2026-11-09','Deepavali'),
  ('2026-12-25','Christmas'),
  -- 2027 public holidays
  ('2027-01-01','New Year'),
  ('2027-02-06','Chinese New Year'),
  ('2027-02-07','Chinese New Year'),
  ('2027-02-16','Thaipusam'),
  ('2027-03-11','Hari Raya Aidilfitri'),
  ('2027-03-12','Hari Raya Aidilfitri'),
  ('2027-05-01','Labour Day'),
  ('2027-05-11','Wesak'),
  ('2027-05-17','Hari Raya Haji'),
  ('2027-06-06','Awal Muharram'),
  ('2027-06-07','Agong Birthday'),
  ('2027-08-16','Maulidur Rasul'),
  ('2027-08-31','National Day'),
  ('2027-09-16','Malaysia Day'),
  ('2027-10-29','Deepavali'),
  ('2027-12-25','Christmas')
ON CONFLICT DO NOTHING;

-- School holiday windows (cuti sekolah). Insert every date in each range as its own row.
-- 2026 windows
DO $$
DECLARE
  v_ranges daterange[] := ARRAY[
    daterange('2026-03-21', '2026-03-30'),   -- Term 1 break (approx)
    daterange('2026-05-23', '2026-05-31'),   -- Mid-term
    daterange('2026-08-22', '2026-08-30'),   -- Term 2 break
    daterange('2026-12-05', '2027-01-04'),   -- Year-end
    daterange('2027-03-13', '2027-03-22'),
    daterange('2027-05-22', '2027-05-30'),
    daterange('2027-08-21', '2027-08-29'),
    daterange('2027-12-04', '2028-01-03')
  ];
  r daterange;
  d date;
BEGIN
  FOREACH r IN ARRAY v_ranges LOOP
    d := lower(r);
    WHILE d < upper(r) LOOP
      INSERT INTO peak_calendar (date, label) VALUES (d, 'School holiday')
      ON CONFLICT DO NOTHING;
      d := d + 1;
    END LOOP;
  END LOOP;
END $$;
```

- [ ] **Step 2: Apply + verify count**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT count(*) FROM peak_calendar WHERE business_id IS NULL;"
```
Expected: > 80 rows (16 public holidays × 2 years + ~60 school-holiday days).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/012_seed_peak_calendar.sql
git commit -m "feat(db): seed MY peak calendar for 2026-2027"
```

---

## Task 19: Dev seed data (for manual exploration in Supabase Studio)

Not part of the migration chain. Lives in `supabase/seed.sql` and runs automatically on `supabase db reset` in local dev. Contains 2 test businesses, 3 kennel types, 2 test owners with pets + certs.

**Files:**
- Modify: `supabase/seed.sql`

- [ ] **Step 1: Replace seed.sql contents**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/supabase/seed.sql`:
```sql
-- Dev-only seed data. Safe to re-run.

-- Auth users
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'owner1@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000002', 'owner2@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000001', 'admin-a@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000002', 'admin-b@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated')
ON CONFLICT DO NOTHING;

INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Dev Owner 1', 'owner'),
  ('10000000-0000-0000-0000-000000000002', 'Dev Owner 2', 'owner'),
  ('20000000-0000-0000-0000-000000000001', 'Admin - Happy Paws KL', 'business_admin'),
  ('20000000-0000-0000-0000-000000000002', 'Admin - Bark Avenue',   'business_admin')
ON CONFLICT DO NOTHING;

-- Pets + certs
INSERT INTO pets (id, owner_id, name, species, breed, weight_kg) VALUES
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Mochi','dog','Poodle',8),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Luna','cat','DSH',4.2)
ON CONFLICT DO NOTHING;

INSERT INTO vaccination_certs (pet_id, file_url, vaccines_covered, issued_on, expires_on) VALUES
  ('30000000-0000-0000-0000-000000000001','https://example.test/cert-mochi.pdf','{rabies,core}','2025-01-15','2027-01-15'),
  ('30000000-0000-0000-0000-000000000002','https://example.test/cert-luna.pdf','{fvrcp}','2025-03-01','2027-03-01')
ON CONFLICT DO NOTHING;

-- Businesses
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status, commission_rate_bps) VALUES
  ('40000000-0000-0000-0000-000000000001','Happy Paws KL','happy-paws-kl','1 Mont Kiara','Kuala Lumpur','WP','verified','active',1200),
  ('40000000-0000-0000-0000-000000000002','Bark Avenue',  'bark-avenue',  '2 Bangsar',   'Kuala Lumpur','WP','verified','active',1200)
ON CONFLICT DO NOTHING;

INSERT INTO business_members (business_id, user_id) VALUES
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002')
ON CONFLICT DO NOTHING;

INSERT INTO listings (id, business_id, amenities, house_rules, cancellation_policy) VALUES
  ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',
    ARRAY['air_con','daily_walks','cctv'],'No aggressive dogs','moderate'),
  ('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002',
    ARRAY['outdoor_run','grooming'],'Vaccinations required','flexible')
ON CONFLICT DO NOTHING;

INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book) VALUES
  ('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','Small Dog Suite','dog','small',4,80,100,true),
  ('60000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001','Large Dog Suite','dog','large',2,120,150,false),
  ('60000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001','Cat Room','cat','small',6,60,75,false),
  ('60000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-000000000002','Large Dog Suite','dog','large',3,95,115,false)
ON CONFLICT DO NOTHING;
```

- [ ] **Step 2: Apply + verify**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase db reset
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT name, slug FROM businesses;"
```
Expected: 2 rows (Happy Paws KL, Bark Avenue).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/seed.sql
git commit -m "chore(db): dev seed data for local exploration"
```

---

## Task 20: End-to-end verification script

A single bash script that exercises the full happy path against a local Supabase instance, as proof of Phase 0 acceptance.

**Files:**
- Create: `supabase/scripts/verify-phase0.sh`

- [ ] **Step 1: Write script**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/scripts/verify-phase0.sh`:
```bash
#!/usr/bin/env bash
# Phase 0 acceptance: exercise the full state machine end-to-end on a fresh local DB.
# Exits non-zero on any failure.

set -euo pipefail

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
")
echo "booking=${BOOKING_ID}"

REF=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='${OWNER}';
  SET LOCAL role='authenticated';
  SELECT create_payment_intent('${BOOKING_ID}'::uuid);
")
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
")
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
")
psql "$DB" -c "SELECT confirm_payment('${REQ_REF}', 240::numeric);"

STATUS=$(psql "$DB" -Atc "SELECT status FROM bookings WHERE id='${REQ_ID}';")
[[ "$STATUS" == "confirmed" ]] || { echo "FAIL: request status is ${STATUS}"; exit 1; }
echo "OK request-to-book → confirmed"

step "5. RLS cross-business isolation"
COUNT=$(psql "$DB" -Atc "
  SET LOCAL request.jwt.claim.sub='20000000-0000-0000-0000-000000000002';
  SET LOCAL role='authenticated';
  SELECT count(*) FROM bookings;
")
[[ "$COUNT" == "0" ]] || { echo "FAIL: Biz B admin sees ${COUNT} bookings, want 0"; exit 1; }
echo "OK Biz B admin sees 0 bookings"

step "6. Sweeps are scheduled"
JOBS=$(psql "$DB" -Atc "SELECT count(*) FROM cron.job WHERE jobname LIKE 'petbnb_%';")
[[ "$JOBS" == "4" ]] || { echo "FAIL: ${JOBS} cron jobs, want 4"; exit 1; }
echo "OK 4 petbnb_* cron jobs scheduled"

step "All Phase 0 checks passed ✓"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/fabian/CodingProject/Primary/PetBnB/supabase/scripts/verify-phase0.sh
```

- [ ] **Step 3: Run it**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
./scripts/verify-phase0.sh
```
Expected: final line "All Phase 0 checks passed ✓".

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/scripts/verify-phase0.sh
git commit -m "test(db): Phase 0 end-to-end verification script"
```

---

## Task 21: README + hand-off doc

Document what Phase 0 delivered and how Phase 1 picks up.

**Files:**
- Modify: `README.md`
- Create: `supabase/README.md`

- [ ] **Step 1: Update root README**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/README.md` with:
```markdown
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
```

- [ ] **Step 2: Write supabase/README.md**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/README.md`:
```markdown
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
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add README.md supabase/README.md
git commit -m "docs: Phase 0 README and handoff"
```

---

## Phase 0 complete — final checklist

Before calling Phase 0 done, verify each:

- [ ] `supabase db reset` applies all 12 migrations without error
- [ ] `supabase test db` passes (9 test files, all assertions green)
- [ ] `./supabase/scripts/verify-phase0.sh` prints "All Phase 0 checks passed ✓"
- [ ] `SELECT count(*) FROM cron.job WHERE jobname LIKE 'petbnb_%'` returns 4
- [ ] `SELECT count(*) FROM peak_calendar WHERE business_id IS NULL` returns > 80
- [ ] RLS: Biz B admin sees 0 bookings when Biz A has some (verified in test 002 and verify-phase0 step 5)
- [ ] `git log --oneline` shows one commit per task (22 commits)

Once all boxes are checked, link this repo to a remote Supabase project:

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/supabase
supabase login
supabase link --project-ref <your-ref>
supabase db push
```

Then update the root README status to `- [x] **Phase 0** — deployed to production`.
