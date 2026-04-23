# PetBnB Phase 1a — Next.js Scaffold, Auth, Drizzle, Business Onboarding

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the business-facing web app so a business admin can sign up, onboard (create their business/members/listing rows via a SECURITY DEFINER RPC), sign in, and land on a routable dashboard skeleton. Foundation for Phases 1b–1d.

**Architecture:** Next.js 15 App Router at `PetBnB/web/`, shares the Phase 0 Supabase project as its backend. Drizzle ORM schema hand-written to match Supabase migrations (no introspection — Supabase CLI remains the migration authority). Supabase Auth via `@supabase/ssr` for server-component-first rendering. All business-creating mutations go through a new `create_business_onboarding` SECURITY DEFINER SQL function because RLS blocks direct INSERT on `businesses`/`business_members` (flagged in Phase 0 final review).

**Tech Stack:**
- Next.js 15 (App Router, TypeScript, React 19)
- Tailwind CSS v4
- shadcn/ui (component library; Button, Input, Label, Card, Avatar, Separator primitives)
- Supabase JS client via `@supabase/ssr`
- Drizzle ORM + drizzle-kit (schema + type generation only; Supabase CLI owns migrations)
- Playwright for E2E smoke tests
- pgTAP for the new SQL function (continues Phase 0 pattern)

**Spec reference:** `/Users/fabian/CodingProject/Primary/docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`
**Phase 0 handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/supabase/README.md`
**Phase 0 plan (already executed):** `/Users/fabian/CodingProject/Primary/docs/superpowers/plans/2026-04-22-petbnb-phase0-schema-and-state-machine.md`

**Scope in this slice:**
- Next.js app scaffold with Tailwind + shadcn/ui
- Drizzle schema TypeScript types for all 15 Phase 0 tables
- `@supabase/ssr` auth wiring: middleware, server client, browser client
- Email + password sign-up and sign-in
- `create_business_onboarding(...)` SECURITY DEFINER RPC + pgTAP test
- Business onboarding form that calls the RPC
- Authenticated dashboard shell with 6-route sidebar (stub pages)
- Playwright E2E smoke test: sign-up → onboarding → dashboard landing

**Out of scope (deferred to 1b+):**
- KYC document upload + Storage buckets (1b)
- Actual listing editor / kennel CRUD (1c)
- Calendar grid, availability management (1d)
- Inbox with pending requests (1d)
- Reviews UI, payouts UI, settings UI (later)
- OAuth providers, magic-link auth, password reset (later)
- i18n (English only for now; spec has `preferred_lang` column)
- Error boundaries beyond basic Next.js defaults

**Phase 1a success criteria:**
1. `cd PetBnB/web && pnpm build` succeeds with no type errors.
2. `pnpm dev` serves the app at http://localhost:3000.
3. A new user can `/sign-up` with email + password, receive confirmation (local Supabase auto-confirms), land on `/onboarding`, submit the form, and arrive at `/dashboard/inbox` — all with the authenticated session persisting across the redirect chain.
4. The onboarding RPC atomically creates rows in `businesses`, `business_members`, and `listings`.
5. `supabase test db` continues to pass all prior assertions plus the new `010_business_onboarding.sql` pgTAP tests.
6. Playwright smoke test `e2e/onboarding.spec.ts` passes end-to-end against local Supabase + local Next.js.
7. RLS isolation still holds: a new business admin cannot read another business's data.

---

## File structure

Phase 1a adds a new `web/` subtree to `/Users/fabian/CodingProject/Primary/PetBnB/` plus one new migration + test in the existing `supabase/` tree. Final layout after Phase 1a:

```
PetBnB/
├── .gitignore               (unchanged)
├── README.md                (updated)
├── supabase/
│   ├── migrations/
│   │   └── 013_business_onboarding.sql   (NEW)
│   ├── tests/
│   │   └── 010_business_onboarding.sql   (NEW)
│   └── … (unchanged Phase 0 files)
└── web/                     (NEW — Next.js app root)
    ├── .env.local.example
    ├── .eslintrc.json
    ├── .gitignore
    ├── README.md
    ├── components.json                 (shadcn config)
    ├── drizzle.config.ts
    ├── middleware.ts                    (Next auth middleware)
    ├── next.config.ts
    ├── package.json
    ├── playwright.config.ts
    ├── postcss.config.mjs
    ├── tailwind.config.ts
    ├── tsconfig.json
    ├── app/
    │   ├── globals.css
    │   ├── layout.tsx                   (root layout)
    │   ├── page.tsx                     (redirect root → /dashboard or /sign-in)
    │   ├── (auth)/
    │   │   ├── sign-in/page.tsx
    │   │   ├── sign-up/page.tsx
    │   │   └── actions.ts               (server actions for auth)
    │   ├── auth/
    │   │   └── callback/route.ts       (session-exchange callback)
    │   ├── onboarding/
    │   │   ├── page.tsx
    │   │   └── actions.ts              (server action: call RPC)
    │   └── dashboard/
    │       ├── layout.tsx              (sidebar + auth guard)
    │       ├── page.tsx                (redirect → inbox)
    │       ├── inbox/page.tsx
    │       ├── calendar/page.tsx
    │       ├── listing/page.tsx
    │       ├── reviews/page.tsx
    │       ├── payouts/page.tsx
    │       └── settings/page.tsx
    ├── components/
    │   ├── ui/                         (shadcn primitives)
    │   │   ├── button.tsx
    │   │   ├── input.tsx
    │   │   ├── label.tsx
    │   │   ├── card.tsx
    │   │   └── separator.tsx
    │   └── dashboard-sidebar.tsx
    ├── lib/
    │   ├── db/
    │   │   ├── index.ts                (Drizzle client factory)
    │   │   └── schema.ts               (hand-written Drizzle schema for all 15 tables)
    │   ├── supabase/
    │   │   ├── client.ts               (browser client)
    │   │   ├── server.ts               (server client)
    │   │   └── middleware.ts           (session refresh helper)
    │   └── utils.ts                    (shadcn cn() helper)
    └── e2e/
        └── onboarding.spec.ts          (Playwright smoke test)
```

**File responsibilities:**
- `web/app/` uses the App Router — server components by default. Server actions (`actions.ts`) handle all mutations.
- `lib/supabase/` provides three client factories for the three contexts: browser (use in client components), server (use in server components/actions), middleware (wraps session refresh).
- `lib/db/schema.ts` is the single source of truth for TypeScript types describing the Postgres schema; read by drizzle-kit for `drizzle-kit studio` + for type-safe queries if we choose to use Drizzle for SELECTs later. Phase 1a itself uses Supabase client directly; Drizzle types are declared but optional for queries.
- Supabase CLI (in `supabase/`) remains the migration authority. Drizzle `push` is intentionally disabled.

---

## Task 1: Next.js scaffold

Bootstrap the `web/` directory with `create-next-app`, commit, verify it runs.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/` (via `create-next-app`)

- [ ] **Step 1: Confirm prerequisites**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
node --version       # >= 20
pnpm --version       # >= 9 (install with corepack: `corepack enable pnpm`)
```

If `pnpm` is missing, install it: `corepack enable pnpm` then `corepack prepare pnpm@latest --activate`.

- [ ] **Step 2: Run create-next-app**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
pnpm create next-app@latest web \
  --ts \
  --tailwind \
  --eslint \
  --app \
  --src-dir=false \
  --import-alias="@/*" \
  --turbopack \
  --use-pnpm \
  --no-git
```

This creates `PetBnB/web/` with TypeScript, Tailwind, ESLint, App Router, no `src/` directory (keep imports short), `@/*` import alias, Turbopack, pnpm, and SKIPS git init (we already have a git repo at the PetBnB root).

- [ ] **Step 3: Verify scaffold runs**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm dev
```

Expected: Server starts at http://localhost:3000 within 5 seconds. Visit the URL — you should see the default Next.js landing page. Ctrl-C to stop.

If port 3000 is in use (e.g. another project), that's fine — stop that process first or use `pnpm dev -- -p 3001` for this verification only. The rest of the plan assumes port 3000.

- [ ] **Step 4: Add `web/.gitignore` entries we care about beyond create-next-app's defaults**

`create-next-app` already creates a `.gitignore` inside `web/` with node_modules, `.next`, etc. Verify and append a few PetBnB-specific entries.

Read `/Users/fabian/CodingProject/Primary/PetBnB/web/.gitignore`. If it does NOT already contain these lines, append them at the end:

```
# env
.env.local
.env.*.local

# playwright
/test-results/
/playwright-report/
/playwright/.cache/

# drizzle
/drizzle/
```

(If any of these lines already exist in the file, don't duplicate them.)

- [ ] **Step 5: Commit scaffold**

From the PetBnB project root:
```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): scaffold Next.js 15 App Router with Tailwind"
```

Expected: `git log --oneline | head -1` shows the new commit. `git status` clean.

---

## Task 2: shadcn/ui init + base primitives

Install shadcn and the six primitives we'll use across Phase 1a.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/components.json`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/utils.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/components/ui/{button,input,label,card,separator}.tsx`

- [ ] **Step 1: Init shadcn**

From `/Users/fabian/CodingProject/Primary/PetBnB/web/`:
```bash
pnpm dlx shadcn@latest init --yes --base-color neutral --css-variables
```

This creates `components.json`, adds `lib/utils.ts` (`cn()` helper), installs `class-variance-authority`, `clsx`, `tailwind-merge`, and adjusts `app/globals.css` with theme CSS variables.

- [ ] **Step 2: Add base components**

```bash
pnpm dlx shadcn@latest add button input label card separator --yes
```

This creates `components/ui/{button,input,label,card,separator}.tsx`.

- [ ] **Step 3: Quick smoke check**

Edit `/Users/fabian/CodingProject/Primary/PetBnB/web/app/page.tsx` — replace entire contents with a brief smoke test using one shadcn component:

```tsx
import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="min-h-screen flex items-center justify-center">
      <Button>PetBnB Phase 1a — scaffold smoke test</Button>
    </main>
  );
}
```

Run `pnpm dev` and visit http://localhost:3000 — should see a dark primary button with the text. Stop the dev server.

We'll rewrite `app/page.tsx` properly in Task 11; this is just to verify shadcn is wired.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): add shadcn/ui primitives (button, input, label, card, separator)"
```

---

## Task 3: Drizzle schema + config

Hand-write the Drizzle schema for all 15 Phase 0 tables so the web app has TypeScript types matching the database. Drizzle-kit is configured with `push: false` — Supabase CLI retains migration ownership.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/drizzle.config.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/db/schema.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/db/index.ts`

- [ ] **Step 1: Install Drizzle**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit @types/pg
```

- [ ] **Step 2: Write `drizzle.config.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/drizzle.config.ts`:
```ts
import { defineConfig } from "drizzle-kit";

// Drizzle is used ONLY for schema-as-code (TypeScript types) and ad-hoc
// introspection via drizzle-kit studio. Supabase CLI migrations are the
// single source of truth for schema changes. Do not run `drizzle-kit push`.
export default defineConfig({
  schema: "./lib/db/schema.ts",
  dialect: "postgresql",
  dbCredentials: {
    url:
      process.env.DATABASE_URL ??
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  },
  verbose: true,
  strict: true,
});
```

- [ ] **Step 3: Write `lib/db/schema.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/db/schema.ts`:
```ts
import {
  pgTable,
  pgEnum,
  uuid,
  text,
  integer,
  numeric,
  boolean,
  date,
  timestamp,
  jsonb,
  primaryKey,
  unique,
  check,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

// ──────────────────────────────────────────────────────────────────────────────
// Enums — mirror supabase/migrations/001_enums.sql
// ──────────────────────────────────────────────────────────────────────────────

export const userRoleEnum = pgEnum("user_role", [
  "owner",
  "business_admin",
  "platform_admin",
]);

export const kycStatusEnum = pgEnum("kyc_status", [
  "pending",
  "verified",
  "rejected",
]);

export const businessStatusEnum = pgEnum("business_status", [
  "active",
  "paused",
  "banned",
]);

export const speciesAcceptedEnum = pgEnum("species_accepted", [
  "dog",
  "cat",
  "both",
]);

export const speciesEnum = pgEnum("species", ["dog", "cat"]);

export const sizeRangeEnum = pgEnum("size_range", [
  "small",
  "medium",
  "large",
]);

export const cancellationPolicyEnum = pgEnum("cancellation_policy", [
  "flexible",
  "moderate",
  "strict",
]);

export const bookingStatusEnum = pgEnum("booking_status", [
  "requested",
  "accepted",
  "declined",
  "pending_payment",
  "expired",
  "confirmed",
  "completed",
  "cancelled_by_owner",
  "cancelled_by_business",
]);

export const bookingTerminalReasonEnum = pgEnum("booking_terminal_reason", [
  "no_response_24h",
  "no_payment_24h",
  "no_payment_15min_instant",
  "owner_cancelled",
  "business_cancelled",
  "payment_failed",
]);

export const notificationKindEnum = pgEnum("notification_kind", [
  "request_submitted",
  "request_accepted",
  "request_declined",
  "payment_confirmed",
  "acceptance_expiring",
  "payment_expiring",
  "booking_cancelled",
  "review_prompt",
  "review_received",
]);

// ──────────────────────────────────────────────────────────────────────────────
// Identity tables — mirror 002_identity_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const userProfiles = pgTable("user_profiles", {
  id: uuid("id").primaryKey(), // FK → auth.users(id); no Drizzle reference because auth schema is Supabase-managed
  displayName: text("display_name").notNull(),
  avatarUrl: text("avatar_url"),
  phone: text("phone"),
  preferredLang: text("preferred_lang").notNull().default("en"),
  primaryRole: userRoleEnum("primary_role").notNull().default("owner"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const pets = pgTable("pets", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  species: speciesEnum("species").notNull(),
  breed: text("breed"),
  ageMonths: integer("age_months"),
  weightKg: numeric("weight_kg", { precision: 5, scale: 2 }),
  medicalNotes: text("medical_notes"),
  avatarUrl: text("avatar_url"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const vaccinationCerts = pgTable("vaccination_certs", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  petId: uuid("pet_id")
    .notNull()
    .references(() => pets.id, { onDelete: "cascade" }),
  fileUrl: text("file_url").notNull(),
  vaccinesCovered: text("vaccines_covered").array().notNull().default(sql`ARRAY[]::text[]`),
  issuedOn: date("issued_on").notNull(),
  expiresOn: date("expires_on").notNull(),
  verifiedByBusinessId: uuid("verified_by_business_id"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Business tables — mirror 003_business_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const businesses = pgTable("businesses", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  address: text("address").notNull(),
  city: text("city").notNull(),
  state: text("state").notNull(),
  // geo_point point -- point not commonly used via Drizzle; skip for typed access
  description: text("description"),
  coverPhotoUrl: text("cover_photo_url"),
  logoUrl: text("logo_url"),
  kycStatus: kycStatusEnum("kyc_status").notNull().default("pending"),
  kycDocuments: jsonb("kyc_documents").notNull().default({}),
  commissionRateBps: integer("commission_rate_bps").notNull().default(1200),
  payoutBankInfo: jsonb("payout_bank_info").notNull().default({}),
  status: businessStatusEnum("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const businessMembers = pgTable(
  "business_members",
  {
    businessId: uuid("business_id")
      .notNull()
      .references(() => businesses.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => userProfiles.id, { onDelete: "cascade" }),
    role: text("role").notNull().default("admin"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.businessId, t.userId] }),
  }),
);

export const listings = pgTable("listings", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  businessId: uuid("business_id")
    .notNull()
    .unique()
    .references(() => businesses.id, { onDelete: "cascade" }),
  photos: text("photos").array().notNull().default(sql`ARRAY[]::text[]`),
  amenities: text("amenities").array().notNull().default(sql`ARRAY[]::text[]`),
  houseRules: text("house_rules"),
  cancellationPolicy: cancellationPolicyEnum("cancellation_policy")
    .notNull()
    .default("moderate"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const kennelTypes = pgTable("kennel_types", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  listingId: uuid("listing_id")
    .notNull()
    .references(() => listings.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  speciesAccepted: speciesAcceptedEnum("species_accepted").notNull(),
  sizeRange: sizeRangeEnum("size_range").notNull(),
  capacity: integer("capacity").notNull(),
  basePriceMyr: numeric("base_price_myr", { precision: 10, scale: 2 }).notNull(),
  peakPriceMyr: numeric("peak_price_myr", { precision: 10, scale: 2 }).notNull(),
  instantBook: boolean("instant_book").notNull().default(false),
  description: text("description"),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Availability — mirror 004_availability_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const peakCalendar = pgTable("peak_calendar", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  businessId: uuid("business_id").references(() => businesses.id, { onDelete: "cascade" }),
  date: date("date").notNull(),
  label: text("label"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const availabilityOverrides = pgTable(
  "availability_overrides",
  {
    id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
    kennelTypeId: uuid("kennel_type_id")
      .notNull()
      .references(() => kennelTypes.id, { onDelete: "cascade" }),
    date: date("date").notNull(),
    manualBlock: boolean("manual_block").notNull().default(true),
    note: text("note"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    uniq: unique().on(t.kennelTypeId, t.date),
  }),
);

// ──────────────────────────────────────────────────────────────────────────────
// Bookings — mirror 005_booking_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const bookings = pgTable("bookings", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  listingId: uuid("listing_id")
    .notNull()
    .references(() => listings.id),
  kennelTypeId: uuid("kennel_type_id")
    .notNull()
    .references(() => kennelTypes.id),
  checkIn: date("check_in").notNull(),
  checkOut: date("check_out").notNull(),
  nights: integer("nights").notNull(),
  subtotalMyr: numeric("subtotal_myr", { precision: 10, scale: 2 }).notNull(),
  platformFeeMyr: numeric("platform_fee_myr", { precision: 10, scale: 2 }).notNull().default("0"),
  businessPayoutMyr: numeric("business_payout_myr", { precision: 10, scale: 2 }).notNull().default("0"),
  status: bookingStatusEnum("status").notNull(),
  requestedAt: timestamp("requested_at", { withTimezone: true }).notNull().defaultNow(),
  actedAt: timestamp("acted_at", { withTimezone: true }),
  paymentDeadline: timestamp("payment_deadline", { withTimezone: true }),
  specialInstructions: text("special_instructions"),
  cancellationReason: text("cancellation_reason"),
  terminalReason: bookingTerminalReasonEnum("terminal_reason"),
  ipay88Reference: text("ipay88_reference").unique(),
  isInstantBook: boolean("is_instant_book").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const bookingPets = pgTable(
  "booking_pets",
  {
    bookingId: uuid("booking_id")
      .notNull()
      .references(() => bookings.id, { onDelete: "cascade" }),
    petId: uuid("pet_id")
      .notNull()
      .references(() => pets.id),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.bookingId, t.petId] }),
  }),
);

export const bookingCertSnapshots = pgTable("booking_cert_snapshots", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  bookingId: uuid("booking_id")
    .notNull()
    .references(() => bookings.id, { onDelete: "cascade" }),
  petId: uuid("pet_id")
    .notNull()
    .references(() => pets.id),
  vaccinationCertId: uuid("vaccination_cert_id")
    .notNull()
    .references(() => vaccinationCerts.id),
  fileUrl: text("file_url").notNull(),
  expiresOn: date("expires_on").notNull(),
  snapshottedAt: timestamp("snapshotted_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Post-stay + ops — mirror 006_post_stay_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const reviews = pgTable("reviews", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  bookingId: uuid("booking_id")
    .notNull()
    .unique()
    .references(() => bookings.id, { onDelete: "cascade" }),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id),
  serviceRating: integer("service_rating").notNull(),
  responseRating: integer("response_rating").notNull(),
  text: text("text"),
  postedAt: timestamp("posted_at", { withTimezone: true }).notNull().defaultNow(),
});

export const reviewResponses = pgTable("review_responses", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  reviewId: uuid("review_id")
    .notNull()
    .unique()
    .references(() => reviews.id, { onDelete: "cascade" }),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  text: text("text").notNull(),
  postedAt: timestamp("posted_at", { withTimezone: true }).notNull().defaultNow(),
});

export const notifications = pgTable("notifications", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: uuid("user_id")
    .notNull()
    .references(() => userProfiles.id, { onDelete: "cascade" }),
  kind: notificationKindEnum("kind").notNull(),
  payload: jsonb("payload").notNull().default({}),
  readAt: timestamp("read_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
```

- [ ] **Step 4: Write `lib/db/index.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/db/index.ts`:
```ts
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

// Connection string for Drizzle. Local dev defaults to the Supabase CLI instance.
// In production this should be the Supabase pooler URL. Not used yet in Phase 1a;
// exposed for Phase 1c+ when we start doing SELECTs via Drizzle (e.g. listing queries).
const connectionString =
  process.env.DATABASE_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const client = postgres(connectionString, {
  prepare: false, // Required when connecting via Supabase pooler; harmless locally
});

export const db = drizzle(client, { schema });
export type DB = typeof db;
```

- [ ] **Step 5: Verify `pnpm build` compiles**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

Expected: build succeeds with no TypeScript errors. If `pnpm build` complains about unused `db` or `DB` exports — that's fine, they're unused in Phase 1a, Next.js treats lib/ files as tree-shakable.

- [ ] **Step 6: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): Drizzle schema for all 15 Phase 0 tables"
```

---

## Task 4: Supabase client factories + auth middleware

Install `@supabase/ssr`, create the three client factories (browser, server, middleware), and wire Next.js middleware to refresh sessions on every request.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/.env.local.example`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/client.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/server.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/middleware.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/middleware.ts`

- [ ] **Step 1: Install package**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm add @supabase/ssr @supabase/supabase-js
```

- [ ] **Step 2: Capture local Supabase keys + write env example**

From `/Users/fabian/CodingProject/Primary/PetBnB/` run `supabase status` and note the `anon key` value. Create `/Users/fabian/CodingProject/Primary/PetBnB/web/.env.local.example`:
```
# Copy to .env.local and fill in. .env.local is gitignored.
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<paste-from-`supabase status`>

# Used by Drizzle tooling (drizzle-kit studio) and by server-side Drizzle queries
# when we start using them in Phase 1c+. Safe to leave pointed at local for dev.
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

Then create a real `.env.local` by copying the example and pasting the anon key from `supabase status`:
```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
cp .env.local.example .env.local
# Edit .env.local manually and replace <paste-from-`supabase status`> with the real value
```

Verify `.env.local` is NOT tracked:
```bash
git check-ignore .env.local
```
Expected output: `.env.local` (meaning: it IS ignored). If no output, the gitignore pattern isn't catching — stop and fix Task 1 Step 4 before continuing.

- [ ] **Step 3: Write `lib/supabase/client.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/client.ts`:
```ts
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
```

Use this in client components via `"use client"` components.

- [ ] **Step 4: Write `lib/supabase/server.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/server.ts`:
```ts
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // setAll called from a Server Component — safe to ignore because
            // middleware.ts refreshes the session on the next request.
          }
        },
      },
    },
  );
}
```

Use this in server components, route handlers, and server actions.

- [ ] **Step 5: Write `lib/supabase/middleware.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/supabase/middleware.ts`:
```ts
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Refresh the session. Cookies are updated on the response if refresh happens.
  // Do not remove this call — it's the only thing refreshing stale JWTs.
  const { data: { user } } = await supabase.auth.getUser();

  // Route-level auth gate: redirect unauthenticated users hitting a protected
  // route to /sign-in. Protected = anything that isn't public.
  const url = request.nextUrl.clone();
  const path = url.pathname;

  const publicRoutes = ["/", "/sign-in", "/sign-up", "/auth/callback"];
  const isPublic =
    publicRoutes.includes(path) ||
    path.startsWith("/_next") ||
    path.startsWith("/api/public");

  if (!user && !isPublic) {
    url.pathname = "/sign-in";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
```

- [ ] **Step 6: Write `middleware.ts` at web root**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/middleware.ts`:
```ts
import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    // Match everything except static assets + images. The middleware
    // still performs auth checks for protected routes internally.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
```

- [ ] **Step 7: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```
Expected: build succeeds, no type errors.

- [ ] **Step 8: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): Supabase Auth client factories + route middleware"
```

---

## Task 5: `create_business_onboarding` SQL function + pgTAP

New migration in `supabase/` that adds the atomic-onboarding SECURITY DEFINER RPC. This is the dependency the Phase 0 final review flagged; nothing on the web side can create businesses without it.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/013_business_onboarding.sql`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/010_business_onboarding.sql`

- [ ] **Step 1: Write failing pgTAP test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/010_business_onboarding.sql`:
```sql
BEGIN;
SELECT plan(7);

-- Create an auth user + profile
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1100-0000-0000-0000-000000000001', 'newadmin@petbnb.test');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('aaaa1100-0000-0000-0000-000000000001', 'New Admin', 'business_admin');

-- Function exists
SELECT has_function('public', 'create_business_onboarding',
  ARRAY['text','text','text','text','text']);

-- Impersonate the user
SET LOCAL request.jwt.claim.sub = 'aaaa1100-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Call the function
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_business_onboarding(
    'Happy Paws Test',
    'happy-paws-test',
    '1 Mont Kiara',
    'Kuala Lumpur',
    'WP'
  );
  PERFORM set_config('petbnb.biz_id', v_id::text, true);
END $$;

-- Business was created with caller as member
SELECT isnt((SELECT current_setting('petbnb.biz_id')), NULL, 'returns a business id');

SELECT is(
  (SELECT name FROM businesses WHERE id = current_setting('petbnb.biz_id')::uuid),
  'Happy Paws Test', 'business name stored correctly');

SELECT is(
  (SELECT count(*)::int FROM business_members
    WHERE business_id = current_setting('petbnb.biz_id')::uuid
      AND user_id = 'aaaa1100-0000-0000-0000-000000000001'),
  1, 'caller is a member of the new business');

SELECT is(
  (SELECT count(*)::int FROM listings
    WHERE business_id = current_setting('petbnb.biz_id')::uuid),
  1, 'stub listing row created');

-- kyc_status defaults to 'pending'
SELECT is(
  (SELECT kyc_status::text FROM businesses WHERE id = current_setting('petbnb.biz_id')::uuid),
  'pending', 'kyc_status defaults to pending');

-- Duplicate slug errors
SELECT throws_like(
  $$ SELECT create_business_onboarding(
      'Happy Paws Test 2', 'happy-paws-test', '2 KL', 'KL', 'WP') $$,
  '%duplicate key%',
  'duplicate slug rejected');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to confirm FAIL**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
```
Expected: the first assertion (`has_function`) fails. That's the desired RED state.

- [ ] **Step 3: Write the migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/013_business_onboarding.sql`:
```sql
-- create_business_onboarding: the only supported path for creating a new
-- business. RLS on businesses + business_members both require caller to be a
-- member; this function bypasses those (SECURITY DEFINER) and atomically
-- creates business + member + stub listing in one transaction.
CREATE OR REPLACE FUNCTION create_business_onboarding(
  p_name text,
  p_slug text,
  p_address text,
  p_city text,
  p_state text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_biz_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'must be authenticated';
  END IF;

  -- Caller must have a user_profile row (sign-up flow inserts this)
  PERFORM 1 FROM user_profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_profile missing for uid %', v_uid;
  END IF;

  -- Basic input validation
  IF coalesce(length(trim(p_name)), 0) = 0 THEN
    RAISE EXCEPTION 'name cannot be empty';
  END IF;
  IF coalesce(length(trim(p_slug)), 0) = 0 THEN
    RAISE EXCEPTION 'slug cannot be empty';
  END IF;
  IF p_slug !~ '^[a-z0-9-]+$' THEN
    RAISE EXCEPTION 'slug must be lowercase alphanumeric with hyphens only';
  END IF;

  -- Insert business (will raise unique_violation on duplicate slug)
  INSERT INTO businesses (name, slug, address, city, state)
  VALUES (trim(p_name), lower(p_slug), trim(p_address), trim(p_city), trim(p_state))
  RETURNING id INTO v_biz_id;

  -- Make caller an admin
  INSERT INTO business_members (business_id, user_id, role)
  VALUES (v_biz_id, v_uid, 'admin');

  -- Stub listing (one listing per business — MVP rule)
  INSERT INTO listings (business_id)
  VALUES (v_biz_id);

  -- Flip the user's role to business_admin if they weren't already
  UPDATE user_profiles SET primary_role = 'business_admin'
  WHERE id = v_uid AND primary_role = 'owner';

  RETURN v_biz_id;
END;
$$;

-- Expose to authenticated users (service_role already has all privileges)
GRANT EXECUTE ON FUNCTION create_business_onboarding(text,text,text,text,text) TO authenticated;
```

- [ ] **Step 4: Apply + re-run tests**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase db reset
supabase test db
```
Expected: all Phase 0 tests pass (51 assertions) + the 7 new Phase 1a assertions = 58 total.

- [ ] **Step 5: Commit**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
git add supabase/migrations/013_business_onboarding.sql supabase/tests/010_business_onboarding.sql
git commit -m "feat(db): create_business_onboarding atomic onboarding RPC"
```

---

## Task 6: Root layout + globals

Overwrite the default create-next-app root layout with PetBnB's version (sets font, metadata).

**Files:**
- Modify: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/layout.tsx`
- Modify: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/globals.css` (verify shadcn init left it intact)

- [ ] **Step 1: Overwrite `app/layout.tsx`**

Replace entire contents of `/Users/fabian/CodingProject/Primary/PetBnB/web/app/layout.tsx` with:
```tsx
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PetBnB — Business Dashboard",
  description:
    "Manage bookings, listings, and payouts for your pet boarding business.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen antialiased bg-white text-neutral-900">
        {children}
      </body>
    </html>
  );
}
```

- [ ] **Step 2: Verify `app/globals.css`**

Open `/Users/fabian/CodingProject/Primary/PetBnB/web/app/globals.css`. It should contain the shadcn theme variables (`:root { --background: ...; ... }` etc.) added by shadcn init in Task 2. If it's still the default create-next-app version without those variables, re-run `pnpm dlx shadcn@latest init --yes --base-color neutral --css-variables` from `web/`.

- [ ] **Step 3: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): root layout and PetBnB metadata"
```

---

## Task 7: Auth pages — sign-up + sign-in + server actions

Email + password flow. Local Supabase auto-confirms emails; in prod we'd add magic link.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/actions.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/sign-in/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/sign-up/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/auth/callback/route.ts`

- [ ] **Step 1: Write `app/(auth)/actions.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AuthFormState = { error?: string };

export async function signUpAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const displayName = String(formData.get("displayName") ?? "").trim();

  if (!email || !password || !displayName) {
    return { error: "All fields are required." };
  }
  if (password.length < 8) {
    return { error: "Password must be at least 8 characters." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName } },
  });
  if (error) return { error: error.message };
  if (!data.user) return { error: "Sign-up did not return a user." };

  // Insert user_profile row (auth trigger isn't set up; we do it from server action).
  // Using rpc-style direct table insert because the user is now authenticated in the
  // response cookies set by signUp; RLS policy user_profiles_self_insert allows this.
  const { error: profileError } = await supabase
    .from("user_profiles")
    .insert({ id: data.user.id, display_name: displayName });
  if (profileError) return { error: `Profile creation failed: ${profileError.message}` };

  revalidatePath("/", "layout");
  redirect("/onboarding");
}

export async function signInAction(
  _prev: AuthFormState,
  formData: FormData,
): Promise<AuthFormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) return { error: "Email and password required." };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message };

  revalidatePath("/", "layout");
  redirect("/dashboard");
}

export async function signOutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath("/", "layout");
  redirect("/sign-in");
}
```

- [ ] **Step 2: Write `app/(auth)/sign-up/page.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/sign-up/page.tsx`:
```tsx
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { signUpAction, type AuthFormState } from "../actions";

export default function SignUpPage() {
  const [state, action, pending] = useActionState<AuthFormState, FormData>(
    signUpAction,
    {},
  );

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-50 p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="text-2xl">Create your business account</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={action} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="displayName">Your name</Label>
              <Input id="displayName" name="displayName" required autoComplete="name" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" name="email" type="email" required autoComplete="email" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input id="password" name="password" type="password" required autoComplete="new-password" minLength={8} />
              <p className="text-xs text-neutral-500">At least 8 characters.</p>
            </div>
            {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
            <Button type="submit" className="w-full" disabled={pending}>
              {pending ? "Creating account…" : "Create account"}
            </Button>
            <p className="text-sm text-neutral-600 text-center">
              Already have an account?{" "}
              <Link href="/sign-in" className="underline">Sign in</Link>
            </p>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
```

- [ ] **Step 3: Write `app/(auth)/sign-in/page.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/(auth)/sign-in/page.tsx`:
```tsx
"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { signInAction, type AuthFormState } from "../actions";

export default function SignInPage() {
  const [state, action, pending] = useActionState<AuthFormState, FormData>(
    signInAction,
    {},
  );

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-50 p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="text-2xl">Sign in to PetBnB</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={action} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" name="email" type="email" required autoComplete="email" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input id="password" name="password" type="password" required autoComplete="current-password" />
            </div>
            {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
            <Button type="submit" className="w-full" disabled={pending}>
              {pending ? "Signing in…" : "Sign in"}
            </Button>
            <p className="text-sm text-neutral-600 text-center">
              New to PetBnB?{" "}
              <Link href="/sign-up" className="underline">Create an account</Link>
            </p>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
```

- [ ] **Step 4: Write `app/auth/callback/route.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/auth/callback/route.ts`:
```ts
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Used by magic-link / OAuth flows. Not exercised by the Phase 1a email+password
// flow (which signs in synchronously), but required for future auth methods.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/dashboard";

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${next}`);
  }
  return NextResponse.redirect(`${origin}/sign-in?error=auth_callback_failed`);
}
```

- [ ] **Step 5: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): sign-up + sign-in pages and auth server actions"
```

---

## Task 8: Onboarding page + server action

Form that calls `create_business_onboarding` RPC.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/onboarding/actions.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/onboarding/page.tsx`

- [ ] **Step 1: Write `app/onboarding/actions.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/onboarding/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type OnboardingFormState = { error?: string };

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
}

export async function createBusinessAction(
  _prev: OnboardingFormState,
  formData: FormData,
): Promise<OnboardingFormState> {
  const name = String(formData.get("name") ?? "").trim();
  const slugRaw = String(formData.get("slug") ?? "").trim();
  const address = String(formData.get("address") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const state = String(formData.get("state") ?? "").trim();

  if (!name || !address || !city || !state) {
    return { error: "Name, address, city, and state are required." };
  }
  const slug = slugRaw || slugify(name);
  if (!/^[a-z0-9-]+$/.test(slug)) {
    return { error: "Slug must be lowercase letters, numbers, and hyphens only." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_business_onboarding", {
    p_name: name,
    p_slug: slug,
    p_address: address,
    p_city: city,
    p_state: state,
  });

  if (error) {
    if (error.code === "23505") {
      return { error: "That slug is already taken. Try another." };
    }
    return { error: error.message };
  }
  if (!data) return { error: "Onboarding did not return a business id." };

  revalidatePath("/", "layout");
  redirect("/dashboard");
}
```

- [ ] **Step 2: Write `app/onboarding/page.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/onboarding/page.tsx`:
```tsx
"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { createBusinessAction, type OnboardingFormState } from "./actions";

export default function OnboardingPage() {
  const [state, action, pending] = useActionState<OnboardingFormState, FormData>(
    createBusinessAction,
    {},
  );

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-50 p-4">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <CardTitle className="text-2xl">Register your business</CardTitle>
          <p className="text-sm text-neutral-600">
            Tell us about your boarding facility. You can edit everything later.
          </p>
        </CardHeader>
        <CardContent>
          <form action={action} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Business name</Label>
              <Input id="name" name="name" required placeholder="Happy Paws KL" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="slug">URL slug (optional)</Label>
              <Input id="slug" name="slug" placeholder="happy-paws-kl" pattern="[a-z0-9-]+" />
              <p className="text-xs text-neutral-500">
                Lowercase letters, numbers, and hyphens. Leave blank to auto-generate from the name.
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="address">Street address</Label>
              <Input id="address" name="address" required placeholder="1 Jalan Mont Kiara" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="city">City</Label>
                <Input id="city" name="city" required placeholder="Kuala Lumpur" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="state">State</Label>
                <Input id="state" name="state" required placeholder="WP Kuala Lumpur" />
              </div>
            </div>
            {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
            <Button type="submit" className="w-full" disabled={pending}>
              {pending ? "Creating…" : "Create business"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
```

- [ ] **Step 3: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): onboarding page calling create_business_onboarding RPC"
```

---

## Task 9: Dashboard shell with sidebar + 6 stub routes

Authenticated-only layout with the 6-route sidebar from the spec/mockups. Each stub page shows a "Coming soon" placeholder.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/components/dashboard-sidebar.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/layout.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/inbox/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/calendar/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/listing/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/reviews/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/payouts/page.tsx`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/settings/page.tsx`

- [ ] **Step 1: Write `components/dashboard-sidebar.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/dashboard-sidebar.tsx`:
```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Separator } from "@/components/ui/separator";
import { signOutAction } from "@/app/(auth)/actions";

type Route = { href: string; label: string };

const routes: Route[] = [
  { href: "/dashboard/inbox", label: "Inbox" },
  { href: "/dashboard/calendar", label: "Calendar" },
  { href: "/dashboard/listing", label: "Listing" },
  { href: "/dashboard/reviews", label: "Reviews" },
  { href: "/dashboard/payouts", label: "Payouts" },
  { href: "/dashboard/settings", label: "Settings" },
];

export function DashboardSidebar({ businessName }: { businessName: string }) {
  const pathname = usePathname();

  return (
    <aside className="w-52 bg-neutral-50 border-r border-neutral-200 flex flex-col">
      <div className="p-4">
        <div className="h-9 w-9 rounded-lg bg-gradient-to-br from-yellow-200 to-orange-400" />
        <div className="mt-2 text-sm font-bold">{businessName}</div>
        <div className="text-xs text-neutral-500">Business admin</div>
      </div>
      <Separator />
      <nav className="py-3 px-2 space-y-1">
        {routes.map((r) => {
          const active = pathname === r.href;
          return (
            <Link
              key={r.href}
              href={r.href}
              className={
                active
                  ? "block rounded-md bg-neutral-900 text-white px-3 py-2 text-xs font-medium"
                  : "block rounded-md text-neutral-700 hover:bg-neutral-100 px-3 py-2 text-xs"
              }
            >
              {r.label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto p-3">
        <form action={signOutAction}>
          <button className="w-full text-left text-xs text-neutral-500 hover:text-neutral-900" type="submit">
            Sign out
          </button>
        </form>
      </div>
    </aside>
  );
}
```

- [ ] **Step 2: Write `app/dashboard/layout.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/layout.tsx`:
```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DashboardSidebar } from "@/components/dashboard-sidebar";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/sign-in");

  // Load the business this admin belongs to. If none, bounce to onboarding.
  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id, businesses!inner(id, name)")
    .eq("user_id", user.id)
    .limit(1)
    .single();

  if (!membership) redirect("/onboarding");

  const businessName =
    (membership.businesses as unknown as { name: string } | null)?.name ??
    "Unknown business";

  return (
    <div className="min-h-screen flex">
      <DashboardSidebar businessName={businessName} />
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
```

- [ ] **Step 3: Write stub route pages**

Create each of the following with the indicated content. Pattern: server component, title + "Coming soon" paragraph.

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/page.tsx`:
```tsx
import { redirect } from "next/navigation";
export default function DashboardIndex() {
  redirect("/dashboard/inbox");
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/inbox/page.tsx`:
```tsx
export default function InboxPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Inbox</h1>
      <p className="text-sm text-neutral-500 mt-1">Pending booking requests.</p>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming in Phase 1d — inbox with pending requests and KPIs.
      </div>
    </div>
  );
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/calendar/page.tsx`:
```tsx
export default function CalendarPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Calendar</h1>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming in Phase 1d — kennel availability grid.
      </div>
    </div>
  );
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/listing/page.tsx`:
```tsx
export default function ListingPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Listing</h1>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming in Phase 1c — listing editor, kennel CRUD, photos.
      </div>
    </div>
  );
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/reviews/page.tsx`:
```tsx
export default function ReviewsPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Reviews</h1>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming later — incoming reviews and response composer.
      </div>
    </div>
  );
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/payouts/page.tsx`:
```tsx
export default function PayoutsPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Payouts</h1>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming later — payout schedule and bank info.
      </div>
    </div>
  );
}
```

`/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/settings/page.tsx`:
```tsx
export default function SettingsPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Settings</h1>
      <div className="mt-8 rounded-lg border border-dashed border-neutral-300 p-10 text-center text-neutral-500">
        Coming later — business profile and team members.
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): dashboard shell with sidebar + 6 stub routes"
```

---

## Task 10: Replace home page `/` with auth-aware redirect

Root path should redirect: signed-in users with a business → `/dashboard`; signed-in users without a business → `/onboarding`; signed-out → `/sign-in`.

**Files:**
- Modify: `/Users/fabian/CodingProject/Primary/PetBnB/web/app/page.tsx`

- [ ] **Step 1: Replace `app/page.tsx`**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/web/app/page.tsx` with:
```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();

  redirect(membership ? "/dashboard" : "/onboarding");
}
```

- [ ] **Step 2: Build + dev smoke test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
pnpm dev
```

In a separate terminal, visit http://localhost:3000. Expected: redirect to `/sign-in` (no session). Go to `/sign-up`, create an account, you should land on `/onboarding`. Submit the form with "Happy Paws Test" / "happy-paws-test" / "1 A St" / "KL" / "WP". Expected: redirect to `/dashboard/inbox` with the sidebar showing "Happy Paws Test".

Stop the dev server.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): auth-aware root route redirects"
```

---

## Task 11: Playwright E2E smoke test

Automate the sign-up → onboarding → dashboard flow.

**Files:**
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/playwright.config.ts`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/onboarding.spec.ts`

- [ ] **Step 1: Install Playwright**

From `/Users/fabian/CodingProject/Primary/PetBnB/web/`:
```bash
pnpm add -D @playwright/test
pnpm exec playwright install --with-deps chromium
```

- [ ] **Step 2: Write `playwright.config.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/playwright.config.ts`:
```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false, // shared DB; don't parallelise
  retries: 0,
  use: {
    baseURL: "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],
  webServer: {
    command: "pnpm dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
```

- [ ] **Step 3: Write `e2e/onboarding.spec.ts`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/onboarding.spec.ts`:
```ts
import { test, expect } from "@playwright/test";

// Helper: generate a unique slug/email so the test doesn't collide with itself
function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("sign-up → onboarding → dashboard", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const displayName = `E2E Admin ${suffix}`;
  const businessName = `E2E Boarding ${suffix}`;
  const slug = `e2e-boarding-${suffix}`;

  // Root redirects unauthenticated → /sign-in
  await page.goto("/");
  await expect(page).toHaveURL(/\/sign-in$/);

  // Go to sign-up
  await page.getByRole("link", { name: /create an account/i }).click();
  await expect(page).toHaveURL(/\/sign-up$/);

  await page.getByLabel("Your name").fill(displayName);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();

  // Should land on /onboarding
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Test Street");
  await page.getByLabel("City").fill("Kuala Lumpur");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();

  // Should end up on dashboard inbox with the business name visible
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);
  await expect(page.getByText(businessName)).toBeVisible();
  await expect(page.getByRole("heading", { name: /inbox/i })).toBeVisible();
});
```

- [ ] **Step 4: Run E2E test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm exec playwright test
```

Expected: 1 passed (the test starts `pnpm dev` in the background itself via `webServer`).

- [ ] **Step 5: Verify Phase 0 still green**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
./supabase/scripts/verify-phase0.sh
```
Expected: all pgTAP assertions pass; verify-phase0 prints "All Phase 0 checks passed ✓".

- [ ] **Step 6: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "test(web): Playwright smoke test for sign-up → onboarding → dashboard"
```

---

## Task 12: README + Phase 1a handoff

Document what Phase 1a delivered and how to run the web app locally.

**Files:**
- Modify: `/Users/fabian/CodingProject/Primary/PetBnB/README.md`
- Create: `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`

- [ ] **Step 1: Update root README**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/README.md` with:
```markdown
# PetBnB

Two-sided marketplace for Malaysian pet boarding. iOS app for owners + Next.js web dashboard for businesses; shared Supabase backend.

**Spec:** `../docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md`

## Status

- [x] **Phase 0** — Supabase schema, RLS, state-machine functions, pg_cron sweeps. See `supabase/README.md`.
- [x] **Phase 1a** — Next.js scaffold, Supabase Auth, Drizzle schema, business onboarding RPC. See `web/README.md`.
- [ ] Phase 1b — KYC upload (Supabase Storage) and documents review
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
```

- [ ] **Step 2: Write `web/README.md`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`:
```markdown
# PetBnB Web (Phase 1a)

Business-facing Next.js 15 App Router app. Backed by the Supabase project at `../supabase`.

## Layout

```
app/
  (auth)/                 sign-up, sign-in, auth server actions
  auth/callback           OAuth/magic-link callback (unused in 1a)
  onboarding/             business registration form + RPC call
  dashboard/              authenticated shell + 6 stub routes
  page.tsx                auth-aware root redirect
lib/
  db/                     Drizzle schema (hand-written to mirror supabase/migrations/)
  supabase/               client / server / middleware factories
  utils.ts                shadcn cn()
components/ui/            shadcn primitives (button, input, label, card, separator)
components/dashboard-sidebar.tsx
e2e/                      Playwright smoke tests
middleware.ts             route-level auth gate
```

## Auth flow

1. `/sign-up` — creates `auth.users` + `user_profiles` rows, redirects to `/onboarding`.
2. `/onboarding` — calls `create_business_onboarding` RPC (SECURITY DEFINER), atomically creates `businesses` + `business_members` + `listings`, redirects to `/dashboard`.
3. `/dashboard/*` — requires auth; if user isn't in any `business_members` row, redirects to `/onboarding`.

All mutations go through server actions (not client-side Supabase calls) so we can revalidate the Next.js cache correctly.

## Drizzle vs Supabase CLI

Supabase CLI owns schema changes (migrations live in `../supabase/migrations/`). Drizzle is used only for TypeScript types and potentially for read queries in later phases. `drizzle-kit push` is never run.

To explore the schema with Drizzle Studio:
```bash
pnpm exec drizzle-kit studio
```

## Handoff to Phase 1b

- KYC document upload goes into `app/dashboard/settings/kyc/page.tsx` and Supabase Storage (`kyc-documents` bucket, private).
- The `businesses.kyc_status` enum already has `pending | verified | rejected`; 1a leaves every new business at `pending` — 1b adds UI to upload docs; platform_admin verifies externally (Supabase Studio) until a later phase builds an internal admin UI.
```

- [ ] **Step 3: Final verification**

Full Phase 1a acceptance — from `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
# Phase 0 still green
supabase test db
./supabase/scripts/verify-phase0.sh

# Web app builds
cd web && pnpm build

# E2E smoke
pnpm exec playwright test
```
All must succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add README.md web/README.md
git commit -m "docs: Phase 1a README and web app handoff"
```

---

## Phase 1a complete — final checklist

Before calling Phase 1a done, verify each:

- [ ] `git log --oneline | head -15` shows 12 new commits on top of Phase 0's 29.
- [ ] `supabase db reset && supabase test db` — all Phase 0 + Phase 1a pgTAP assertions pass (58+ total).
- [ ] `cd web && pnpm build` — no type errors, no ESLint errors.
- [ ] `cd web && pnpm exec playwright test` — E2E smoke passes.
- [ ] `cd web && pnpm dev` — manual sign-up → onboarding → dashboard flow works in a browser.
- [ ] `./supabase/scripts/verify-phase0.sh` — still green.
- [ ] No credentials committed: `git log -p | grep -E "eyJ[A-Za-z0-9_-]{20,}"` is empty.

Once all boxes are checked, push to GitHub:
```bash
git push origin main
```

Then plan Phase 1b.
