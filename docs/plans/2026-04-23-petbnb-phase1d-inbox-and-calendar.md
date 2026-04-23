# PetBnB Phase 1d — Real Inbox + Calendar/Availability

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `/dashboard/inbox` and `/dashboard/calendar` routes from stubs into real features. Business admins see pending booking requests, accept or decline them (invoking Phase 0's existing state-machine RPCs), and manage kennel-day availability via a 14-day grid. Completes Phase 1 — after this, the business dashboard is functionally whole and iOS (Phase 2) can consume a live, tested backend.

**Architecture:** Add two cross-user-scoped RLS policies (one on `pets`, one on `user_profiles`) so business admins can SELECT the customer data needed for Inbox rendering. All write paths reuse Phase 0 RPCs (`accept_booking`, `decline_booking`) — no new SQL functions. Availability blocks manipulated via direct `availability_overrides` inserts/deletes under existing RLS (Phase 0's `availability_overrides_member_all` policy covers member write access). Calendar UI renders a 14-day window with week-forward/week-back navigation; URL state (`?start=YYYY-MM-DD`) drives what's displayed so browser back/forward work.

**Tech Stack (unchanged):**
- Next.js 16 App Router + server actions + server components (query via `@supabase/ssr`)
- Tailwind + shadcn/ui (no new primitives)
- pgTAP for the new RLS
- Playwright for E2E

**Spec references:** §9 (business dashboard — Inbox + Calendar routes)
**Phase 1c handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`

**Scope in this slice:**
- Migration 017: `pets_business_read` + `user_profiles_business_read` RLS policies
- pgTAP proving the new scope (business sees own customer pets/profiles, not anyone else's)
- Inbox page: real pending-request list + accept/decline buttons + KPI strip (pending, today check-in, today check-out, week revenue)
- Calendar page: 14-day kennel × date grid + click-to-toggle manual block + week navigation
- Server actions: `acceptBookingAction`, `declineBookingAction`, `toggleAvailabilityBlockAction`
- Playwright E2E: seed a `requested` booking via service-role SQL, business admin accepts it, verify status=`accepted`
- README updates marking Phase 1 complete

**Out of scope (explicitly deferred):**
- Supabase Realtime on the business dashboard — polling via server component re-render is fine; spec §8 only mandates Realtime for the iOS owner surface
- Drag-to-block date ranges on the calendar — click-per-cell MVP; drag is 5+ polish
- In-app messaging owner↔business — separate later slice
- Bulk actions (accept all / decline all) — no spec need
- CSV export — defer
- Owner profile detail page — display name only for now
- Per-kennel calendar drill-down — single grid shows all kennels at once
- Booking detail page (drilling into a confirmed/completed booking) — defer to a later phase; Inbox cards are terminal for the request-review flow
- Response-time KPI history visualization — current response time is displayed, but no time-series graph (later phase)

**Phase 1d success criteria:**
1. With a seeded `requested` booking in the DB, signing in as the business admin and visiting `/dashboard/inbox` shows the booking card with pet name, owner display name, check-in/check-out, nights, total MYR, and cert-attached indicator.
2. Clicking Accept transitions the booking to `accepted` state; clicking Decline transitions to `declined`. Both update the UI immediately (via `router.refresh()`).
3. `/dashboard/calendar` renders a 14-day grid with kennel rows and date columns. Confirmed bookings are visually distinct from pending/accepted, and manual blocks show as red.
4. Clicking a cell with no booking toggles a manual block on/off; the click persists and the cell color flips.
5. pgTAP test passes: business A admin can SELECT the pet + user_profile rows for their customers but not for business B's customers.
6. Playwright E2E passes: seed booking → sign in → accept → verify DB row shows `accepted`.
7. `supabase test db` all assertions pass; existing E2E tests unchanged.
8. `cd web && pnpm build` clean.

---

## File structure

```
PetBnB/
├── supabase/
│   ├── migrations/
│   │   └── 017_inbox_visibility_rls.sql    (NEW)
│   └── tests/
│       └── 013_inbox_visibility_rls.sql    (NEW)
└── web/
    ├── app/
    │   └── dashboard/
    │       ├── inbox/
    │       │   ├── page.tsx                  (REPLACES 1a stub)
    │       │   └── actions.ts                (NEW — accept/decline)
    │       └── calendar/
    │           ├── page.tsx                  (REPLACES 1a stub)
    │           └── actions.ts                (NEW — toggle block)
    ├── components/
    │   ├── booking-request-card.tsx          (NEW)
    │   ├── inbox-kpi-strip.tsx               (NEW)
    │   └── availability-grid.tsx             (NEW)
    └── e2e/
        └── accept-booking.spec.ts            (NEW)
```

---

## Task 1: Inbox RLS migration — cross-user reads for business admins

Spec §9 Inbox cards show `<pet_name> · <breed> · <weight>` and `Owner: <display_name>`. Phase 0 RLS blocks business admins from reading `pets` or `user_profiles` rows owned by other users. Add two scoped SELECT policies.

**Files:**
- Create: `supabase/migrations/017_inbox_visibility_rls.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/017_inbox_visibility_rls.sql`:
```sql
-- Business admins need to see pet + owner info for rendering the Inbox UI.
-- Scope: only rows linked to a booking at their own business.

-- pets: business_admin SELECT if any booking_pets row connects this pet to a
-- booking at caller's business.
CREATE POLICY pets_business_read ON pets
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM booking_pets bp
      JOIN bookings b ON b.id = bp.booking_id
      WHERE bp.pet_id = pets.id
        AND is_business_member(b.business_id)
    )
  );

-- user_profiles: business_admin SELECT if this user has any booking at caller's
-- business.
CREATE POLICY user_profiles_business_read ON user_profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.owner_id = user_profiles.id
        AND is_business_member(b.business_id)
    )
  );
```

- [ ] **Step 2: Apply**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase db reset
```
Expected: succeeds, no errors.

- [ ] **Step 3: Verify policies**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT tablename, policyname FROM pg_policies WHERE policyname IN ('pets_business_read','user_profiles_business_read') ORDER BY tablename;"
```
Expected: two rows.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/017_inbox_visibility_rls.sql
git commit -m "feat(db): business admin can read pets + profiles of their customers"
```

---

## Task 2: pgTAP — prove the new RLS scope

**Files:**
- Create: `supabase/tests/013_inbox_visibility_rls.sql`

- [ ] **Step 1: Write test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/013_inbox_visibility_rls.sql`:
```sql
BEGIN;
SELECT plan(6);

-- Two businesses, two owners. Owner A books at biz A; owner B books at biz B.
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1d00-0000-0000-0000-000000000001', 'admin-a@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000002', 'admin-b@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000011', 'owner-a@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000012', 'owner-b@1d.t');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('aaaa1d00-0000-0000-0000-000000000001', 'Admin A', 'business_admin'),
  ('aaaa1d00-0000-0000-0000-000000000002', 'Admin B', 'business_admin'),
  ('aaaa1d00-0000-0000-0000-000000000011', 'Owner A', 'owner'),
  ('aaaa1d00-0000-0000-0000-000000000012', 'Owner B', 'owner');

INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('bbbb1d00-0000-0000-0000-000000000001', 'Biz A-1d', 'biz-a-1d', '1 A', 'KL', 'WP', 'verified', 'active'),
  ('bbbb1d00-0000-0000-0000-000000000002', 'Biz B-1d', 'biz-b-1d', '1 B', 'KL', 'WP', 'verified', 'active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('bbbb1d00-0000-0000-0000-000000000001', 'aaaa1d00-0000-0000-0000-000000000001'),
  ('bbbb1d00-0000-0000-0000-000000000002', 'aaaa1d00-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('cccc1d00-0000-0000-0000-000000000001', 'bbbb1d00-0000-0000-0000-000000000001'),
  ('cccc1d00-0000-0000-0000-000000000002', 'bbbb1d00-0000-0000-0000-000000000002');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES
  ('dddd1d00-0000-0000-0000-000000000001', 'cccc1d00-0000-0000-0000-000000000001', 'A-K', 'dog', 'small', 4, 80, 100),
  ('dddd1d00-0000-0000-0000-000000000002', 'cccc1d00-0000-0000-0000-000000000002', 'B-K', 'dog', 'small', 4, 80, 100);

-- Pets
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('eeee1d00-0000-0000-0000-000000000a01', 'aaaa1d00-0000-0000-0000-000000000011', 'PetA', 'dog'),
  ('eeee1d00-0000-0000-0000-000000000b01', 'aaaa1d00-0000-0000-0000-000000000012', 'PetB', 'dog');

-- Bookings (owner A → biz A; owner B → biz B)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status)
VALUES
  ('ffff1d00-0000-0000-0000-000000000001',
   'aaaa1d00-0000-0000-0000-000000000011',
   'bbbb1d00-0000-0000-0000-000000000001',
   'cccc1d00-0000-0000-0000-000000000001',
   'dddd1d00-0000-0000-0000-000000000001',
   '2027-01-01', '2027-01-03', 2, 160, 'requested'),
  ('ffff1d00-0000-0000-0000-000000000002',
   'aaaa1d00-0000-0000-0000-000000000012',
   'bbbb1d00-0000-0000-0000-000000000002',
   'cccc1d00-0000-0000-0000-000000000002',
   'dddd1d00-0000-0000-0000-000000000002',
   '2027-01-01', '2027-01-03', 2, 160, 'requested');
INSERT INTO booking_pets (booking_id, pet_id) VALUES
  ('ffff1d00-0000-0000-0000-000000000001', 'eeee1d00-0000-0000-0000-000000000a01'),
  ('ffff1d00-0000-0000-0000-000000000002', 'eeee1d00-0000-0000-0000-000000000b01');

-- Impersonate Admin A
SET LOCAL request.jwt.claim.sub = 'aaaa1d00-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Sees PetA
SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000a01'),
  1, 'Admin A can read own customer pet');

-- Does NOT see PetB
SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000b01'),
  0, 'Admin A cannot read Biz B customer pet');

-- Sees Owner A profile
SELECT is(
  (SELECT count(*)::int FROM user_profiles WHERE id = 'aaaa1d00-0000-0000-0000-000000000011'),
  1, 'Admin A can read own customer profile');

-- Does NOT see Owner B profile
SELECT is(
  (SELECT count(*)::int FROM user_profiles WHERE id = 'aaaa1d00-0000-0000-0000-000000000012'),
  0, 'Admin A cannot read Biz B customer profile');

-- Impersonate Admin B
RESET role;
SET LOCAL request.jwt.claim.sub = 'aaaa1d00-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000b01'),
  1, 'Admin B can read own customer pet');

SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000a01'),
  0, 'Admin B cannot read Biz A customer pet');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
```
Expected: 74 assertions passing (68 prior + 6 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/013_inbox_visibility_rls.sql
git commit -m "test(db): business admin sees only own customers' pets + profiles"
```

---

## Task 3: Server actions — accept / decline / toggle availability block

**Files:**
- Create: `web/app/dashboard/inbox/actions.ts`
- Create: `web/app/dashboard/calendar/actions.ts`

- [ ] **Step 1: Write inbox actions**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/inbox/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type InboxActionState = { error?: string; ok?: true };

export async function acceptBookingAction(
  _prev: InboxActionState,
  formData: FormData,
): Promise<InboxActionState> {
  const bookingId = String(formData.get("booking_id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(bookingId)) return { error: "Invalid booking id" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("accept_booking", { p_booking_id: bookingId });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/inbox");
  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

export async function declineBookingAction(
  _prev: InboxActionState,
  formData: FormData,
): Promise<InboxActionState> {
  const bookingId = String(formData.get("booking_id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(bookingId)) return { error: "Invalid booking id" };
  const reason = (formData.get("reason") as string | null)?.trim() || null;

  const supabase = await createClient();
  const { error } = await supabase.rpc("decline_booking", {
    p_booking_id: bookingId,
    p_reason: reason,
  });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/inbox");
  return { ok: true };
}
```

- [ ] **Step 2: Write calendar actions**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/calendar/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type CalendarActionState = { error?: string; ok?: true };

export async function toggleAvailabilityBlockAction(
  _prev: CalendarActionState,
  formData: FormData,
): Promise<CalendarActionState> {
  const kennelId = String(formData.get("kennel_type_id") ?? "");
  const date = String(formData.get("date") ?? "");

  if (!/^[0-9a-f-]{36}$/.test(kennelId)) return { error: "Invalid kennel id" };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "Invalid date" };

  const supabase = await createClient();

  // Guard: caller must belong to the kennel's business (RLS would catch this
  // but an explicit error is clearer than a silent 0-row response).
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("id, listings!inner(business_id)")
    .eq("id", kennelId)
    .maybeSingle();
  if (!kennel) return { error: "Kennel not found or not yours" };

  // Is there already a block row for this (kennel, date)?
  const { data: existing } = await supabase
    .from("availability_overrides")
    .select("id, manual_block")
    .eq("kennel_type_id", kennelId)
    .eq("date", date)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from("availability_overrides")
      .delete()
      .eq("id", existing.id);
    if (error) return { error: error.message };
  } else {
    const { error } = await supabase.from("availability_overrides").insert({
      kennel_type_id: kennelId,
      date,
      manual_block: true,
    });
    if (error) return { error: error.message };
  }

  revalidatePath("/dashboard/calendar");
  return { ok: true };
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
git add web/app/dashboard/inbox/actions.ts web/app/dashboard/calendar/actions.ts
git commit -m "feat(web): inbox + calendar server actions"
```

---

## Task 4: BookingRequestCard + InboxKpiStrip components

**Files:**
- Create: `web/components/booking-request-card.tsx`
- Create: `web/components/inbox-kpi-strip.tsx`

- [ ] **Step 1: Write BookingRequestCard**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/booking-request-card.tsx`:
```tsx
"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  acceptBookingAction,
  declineBookingAction,
  type InboxActionState,
} from "@/app/dashboard/inbox/actions";

export type BookingRequestView = {
  id: string;
  check_in: string;
  check_out: string;
  nights: number;
  subtotal_myr: string;
  special_instructions: string | null;
  requested_at: string;
  pets: { name: string; species: string; breed: string | null; weight_kg: string | null }[];
  owner: { display_name: string };
  kennel: { name: string };
  cert_attached: boolean;
};

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-MY", { day: "numeric", month: "short" });
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-MY", { dateStyle: "medium", timeStyle: "short" });
}

export function BookingRequestCard({ req }: { req: BookingRequestView }) {
  const router = useRouter();
  const [acceptState, acceptAction, acceptPending] = useActionState<InboxActionState, FormData>(
    acceptBookingAction,
    {},
  );
  const [declineState, declineAction, declinePending] = useActionState<InboxActionState, FormData>(
    declineBookingAction,
    {},
  );

  useEffect(() => {
    if (acceptState.ok || declineState.ok) router.refresh();
  }, [acceptState.ok, declineState.ok, router]);

  const error = acceptState.error ?? declineState.error;
  const pending = acceptPending || declinePending;

  return (
    <Card className="border-neutral-200">
      <CardContent className="p-5 space-y-3">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h3 className="font-semibold">{req.kennel.name}</h3>
            <p className="text-xs text-neutral-500">
              {formatDate(req.check_in)} → {formatDate(req.check_out)} · {req.nights} night{req.nights === 1 ? "" : "s"} · RM{Number(req.subtotal_myr).toFixed(2)}
            </p>
            <p className="text-xs text-neutral-500 mt-0.5">
              Owner: <strong className="text-neutral-900">{req.owner.display_name}</strong> · requested {formatDateTime(req.requested_at)}
            </p>
          </div>
          {req.cert_attached ? (
            <span className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-md px-2 py-1">
              Vaccination cert attached
            </span>
          ) : (
            <span className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-2 py-1">
              No cert on file
            </span>
          )}
        </div>

        <div className="rounded-md bg-neutral-50 border border-neutral-200 px-3 py-2 text-xs">
          <div className="font-medium text-neutral-900 mb-1">Pets</div>
          <ul className="space-y-0.5">
            {req.pets.map((p, i) => (
              <li key={i} className="text-neutral-700">
                {p.name}
                {p.breed ? ` · ${p.breed}` : ""}
                {p.weight_kg ? ` · ${Number(p.weight_kg).toFixed(1)} kg` : ""}
              </li>
            ))}
          </ul>
        </div>

        {req.special_instructions ? (
          <div className="rounded-md bg-neutral-50 border border-neutral-200 px-3 py-2 text-xs">
            <div className="font-medium text-neutral-900 mb-1">Notes from owner</div>
            <p className="text-neutral-700 whitespace-pre-wrap">{req.special_instructions}</p>
          </div>
        ) : null}

        {error ? <p className="text-sm text-red-600">{error}</p> : null}

        <div className="flex gap-2 justify-end pt-2">
          <form action={declineAction}>
            <input type="hidden" name="booking_id" value={req.id} />
            <Button type="submit" variant="outline" size="sm" disabled={pending}>
              {declinePending ? "Declining…" : "Decline"}
            </Button>
          </form>
          <form action={acceptAction}>
            <input type="hidden" name="booking_id" value={req.id} />
            <Button type="submit" size="sm" disabled={pending}>
              {acceptPending ? "Accepting…" : "Accept"}
            </Button>
          </form>
        </div>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Write InboxKpiStrip**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/inbox-kpi-strip.tsx`:
```tsx
import { Card, CardContent } from "@/components/ui/card";

export type InboxKpis = {
  pending: number;
  todayCheckIn: number;
  todayCheckOut: number;
  weekRevenueMyr: number;
};

export function InboxKpiStrip({ kpis }: { kpis: InboxKpis }) {
  const items: { label: string; value: string }[] = [
    { label: "Pending", value: String(kpis.pending) },
    { label: "Today check-in", value: String(kpis.todayCheckIn) },
    { label: "Today check-out", value: String(kpis.todayCheckOut) },
    { label: "This week", value: `RM${kpis.weekRevenueMyr.toFixed(0)}` },
  ];
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
      {items.map((i) => (
        <Card key={i.label} className="border-neutral-200">
          <CardContent className="p-3">
            <div className="text-[10px] uppercase tracking-wide text-neutral-500 font-semibold">
              {i.label}
            </div>
            <div className="text-xl font-bold mt-0.5">{i.value}</div>
          </CardContent>
        </Card>
      ))}
    </div>
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
git add web/components/booking-request-card.tsx web/components/inbox-kpi-strip.tsx
git commit -m "feat(web): booking request card + inbox KPI strip components"
```

---

## Task 5: Inbox page

**Files:**
- Modify: `web/app/dashboard/inbox/page.tsx` (replaces 1a stub)

- [ ] **Step 1: Overwrite page**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/inbox/page.tsx`:
```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { BookingRequestCard, type BookingRequestView } from "@/components/booking-request-card";
import { InboxKpiStrip, type InboxKpis } from "@/components/inbox-kpi-strip";

export const dynamic = "force-dynamic";

export default async function InboxPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const businessId = membership.business_id;

  // Pending requests with joined pets, owner, kennel, and cert presence
  const { data: requestsRaw, error: reqErr } = await supabase
    .from("bookings")
    .select(`
      id, check_in, check_out, nights, subtotal_myr, special_instructions, requested_at, owner_id,
      kennel_types!inner(name),
      booking_pets(pet_id),
      booking_cert_snapshots(id)
    `)
    .eq("business_id", businessId)
    .eq("status", "requested")
    .order("requested_at", { ascending: true });
  if (reqErr) throw new Error(reqErr.message);

  // Hydrate owner profiles + pets in batch
  const ownerIds = Array.from(new Set((requestsRaw ?? []).map((r) => r.owner_id)));
  const petIds = Array.from(
    new Set(
      (requestsRaw ?? []).flatMap((r) => (r.booking_pets as { pet_id: string }[]).map((bp) => bp.pet_id)),
    ),
  );

  const [{ data: profiles }, { data: pets }] = await Promise.all([
    ownerIds.length > 0
      ? supabase.from("user_profiles").select("id, display_name").in("id", ownerIds)
      : Promise.resolve({ data: [] as { id: string; display_name: string }[] }),
    petIds.length > 0
      ? supabase.from("pets").select("id, name, species, breed, weight_kg").in("id", petIds)
      : Promise.resolve({
          data: [] as {
            id: string; name: string; species: string; breed: string | null; weight_kg: string | null;
          }[],
        }),
  ]);

  const profileById = new Map((profiles ?? []).map((p) => [p.id, p.display_name]));
  const petById = new Map((pets ?? []).map((p) => [p.id, p]));

  const requests: BookingRequestView[] = (requestsRaw ?? []).map((r) => ({
    id: r.id,
    check_in: r.check_in,
    check_out: r.check_out,
    nights: r.nights,
    subtotal_myr: r.subtotal_myr,
    special_instructions: r.special_instructions,
    requested_at: r.requested_at,
    pets: (r.booking_pets as { pet_id: string }[]).flatMap((bp) => {
      const p = petById.get(bp.pet_id);
      return p ? [{ name: p.name, species: p.species, breed: p.breed, weight_kg: p.weight_kg }] : [];
    }),
    owner: { display_name: profileById.get(r.owner_id) ?? "Unknown" },
    kennel: { name: (r.kennel_types as unknown as { name: string }).name },
    cert_attached: (r.booking_cert_snapshots as unknown[]).length > 0,
  }));

  // KPIs
  const todayIso = new Date().toISOString().slice(0, 10);
  const weekStart = todayIso;
  const weekEnd = new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10);

  const [{ count: pendingCount }, { count: todayIn }, { count: todayOut }, { data: weekRows }] =
    await Promise.all([
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "requested"),
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "confirmed")
        .eq("check_in", todayIso),
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "confirmed")
        .eq("check_out", todayIso),
      supabase
        .from("bookings")
        .select("business_payout_myr, check_in")
        .eq("business_id", businessId)
        .in("status", ["confirmed", "completed"])
        .gte("check_in", weekStart)
        .lt("check_in", weekEnd),
    ]);

  const weekRevenue = (weekRows ?? []).reduce((sum, r) => sum + Number(r.business_payout_myr), 0);

  const kpis: InboxKpis = {
    pending: pendingCount ?? 0,
    todayCheckIn: todayIn ?? 0,
    todayCheckOut: todayOut ?? 0,
    weekRevenueMyr: weekRevenue,
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Inbox</h1>
        <p className="text-sm text-neutral-600 mt-1">
          Pending booking requests and today's activity.
        </p>
      </div>

      <InboxKpiStrip kpis={kpis} />

      <div className="space-y-4">
        <div className="text-[11px] uppercase tracking-wider text-neutral-500 font-semibold">
          Pending requests
        </div>
        {requests.length === 0 ? (
          <div className="rounded-md border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-500">
            No pending requests.
          </div>
        ) : (
          requests.map((r) => <BookingRequestCard key={r.id} req={r} />)
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Build + manual smoke test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/app/dashboard/inbox/page.tsx
git commit -m "feat(web): inbox page with real pending-request list + KPIs"
```

---

## Task 6: AvailabilityGrid component + Calendar page

**Files:**
- Create: `web/components/availability-grid.tsx`
- Modify: `web/app/dashboard/calendar/page.tsx` (replaces 1a stub)

- [ ] **Step 1: Write AvailabilityGrid**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/availability-grid.tsx`:
```tsx
"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  toggleAvailabilityBlockAction,
  type CalendarActionState,
} from "@/app/dashboard/calendar/actions";

export type KennelRow = { id: string; name: string; capacity: number };

/** For each (kennel_type_id, date) pair, how many bookings occupy the cell
 *  and whether a manual block is present. */
export type CellState = {
  bookings: number; // count of accepted+confirmed+pending_payment bookings covering this date
  manual_block: boolean;
};

export type CellMap = Record<string, CellState>; // key = `${kennel_type_id}|${date}`

function formatShort(d: Date) {
  return d.toLocaleDateString("en-MY", { day: "2-digit", month: "short" });
}

function formatWeekday(d: Date) {
  return d.toLocaleDateString("en-MY", { weekday: "short" });
}

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

function addDays(d: Date, n: number) {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

export function AvailabilityGrid({
  kennels,
  startDate,
  days,
  cells,
}: {
  kennels: KennelRow[];
  startDate: string; // YYYY-MM-DD (the first column)
  days: number;
  cells: CellMap;
}) {
  const router = useRouter();
  const [state, toggleAction, pending] = useActionState<CalendarActionState, FormData>(
    toggleAvailabilityBlockAction,
    {},
  );

  useEffect(() => {
    if (state.ok) router.refresh();
  }, [state.ok, router]);

  const start = new Date(`${startDate}T00:00:00`);
  const dayList = Array.from({ length: days }, (_, i) => addDays(start, i));

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-xs border-collapse">
        <thead>
          <tr>
            <th className="text-left font-semibold text-neutral-500 px-3 py-2 border-b border-neutral-200">
              Kennel
            </th>
            {dayList.map((d) => (
              <th
                key={isoDate(d)}
                className="text-center font-semibold text-neutral-500 px-1 py-2 border-b border-neutral-200 min-w-[56px]"
              >
                <div>{formatWeekday(d)}</div>
                <div className="text-neutral-900">{formatShort(d)}</div>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {kennels.map((k) => (
            <tr key={k.id}>
              <th className="text-left font-medium text-neutral-900 px-3 py-2 border-b border-neutral-100">
                {k.name}
                <div className="text-[10px] text-neutral-500 font-normal">cap {k.capacity}</div>
              </th>
              {dayList.map((d) => {
                const date = isoDate(d);
                const key = `${k.id}|${date}`;
                const cell = cells[key] ?? { bookings: 0, manual_block: false };
                const isFull = cell.bookings >= k.capacity;
                const className = cell.manual_block
                  ? "bg-red-100 border-red-200"
                  : isFull
                  ? "bg-neutral-900 border-neutral-900"
                  : cell.bookings > 0
                  ? "bg-amber-100 border-amber-200"
                  : "bg-white border-neutral-200";

                return (
                  <td
                    key={key}
                    className="p-0 border-b border-neutral-100"
                  >
                    <form action={toggleAction}>
                      <input type="hidden" name="kennel_type_id" value={k.id} />
                      <input type="hidden" name="date" value={date} />
                      <button
                        type="submit"
                        disabled={pending || cell.bookings > 0}
                        title={
                          cell.bookings > 0
                            ? `${cell.bookings} booking(s)`
                            : cell.manual_block
                            ? "Manual block — click to unblock"
                            : "Click to block"
                        }
                        className={`w-full h-10 border ${className} transition cursor-pointer disabled:cursor-not-allowed`}
                      >
                        <span
                          className={
                            cell.manual_block
                              ? "text-red-900 font-semibold"
                              : isFull
                              ? "text-white"
                              : cell.bookings > 0
                              ? "text-amber-900"
                              : "text-neutral-400"
                          }
                        >
                          {cell.manual_block ? "✕" : cell.bookings > 0 ? `${cell.bookings}/${k.capacity}` : "·"}
                        </span>
                      </button>
                    </form>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
      {state.error ? <p className="text-sm text-red-600 mt-2">{state.error}</p> : null}
    </div>
  );
}
```

- [ ] **Step 2: Overwrite Calendar page**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/calendar/page.tsx`:
```tsx
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AvailabilityGrid, type CellMap, type KennelRow } from "@/components/availability-grid";

export const dynamic = "force-dynamic";

const WINDOW_DAYS = 14;

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function addDays(iso: string, n: number): string {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + n);
  return isoDate(d);
}
function todayIso(): string {
  return isoDate(new Date());
}

export default async function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<{ start?: string }>;
}) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const params = await searchParams;
  const startParam = params.start;
  const startDate = startParam && /^\d{4}-\d{2}-\d{2}$/.test(startParam) ? startParam : todayIso();
  const endDate = addDays(startDate, WINDOW_DAYS); // exclusive end

  const { data: listing } = await supabase
    .from("listings")
    .select("id")
    .eq("business_id", membership.business_id)
    .single();

  const { data: kennelsRaw } = await supabase
    .from("kennel_types")
    .select("id, name, capacity")
    .eq("listing_id", listing?.id ?? "")
    .eq("active", true)
    .order("created_at", { ascending: true });
  const kennels: KennelRow[] = (kennelsRaw ?? []) as KennelRow[];

  // Occupancy: count accepted/pending_payment/confirmed bookings overlapping each day.
  const kennelIds = kennels.map((k) => k.id);
  const [{ data: bookingsRaw }, { data: overridesRaw }] = await Promise.all([
    kennelIds.length > 0
      ? supabase
          .from("bookings")
          .select("kennel_type_id, check_in, check_out, status")
          .in("kennel_type_id", kennelIds)
          .in("status", ["accepted", "pending_payment", "confirmed"])
          .gte("check_out", startDate)
          .lte("check_in", endDate)
      : Promise.resolve({ data: [] as { kennel_type_id: string; check_in: string; check_out: string; status: string }[] }),
    kennelIds.length > 0
      ? supabase
          .from("availability_overrides")
          .select("kennel_type_id, date, manual_block")
          .in("kennel_type_id", kennelIds)
          .gte("date", startDate)
          .lt("date", endDate)
      : Promise.resolve({ data: [] as { kennel_type_id: string; date: string; manual_block: boolean }[] }),
  ]);

  // Build cells map
  const cells: CellMap = {};
  for (const b of bookingsRaw ?? []) {
    let cursor = b.check_in;
    while (cursor < b.check_out) {
      if (cursor >= startDate && cursor < endDate) {
        const key = `${b.kennel_type_id}|${cursor}`;
        const prev = cells[key] ?? { bookings: 0, manual_block: false };
        cells[key] = { ...prev, bookings: prev.bookings + 1 };
      }
      cursor = addDays(cursor, 1);
    }
  }
  for (const o of overridesRaw ?? []) {
    if (!o.manual_block) continue;
    const key = `${o.kennel_type_id}|${o.date}`;
    const prev = cells[key] ?? { bookings: 0, manual_block: false };
    cells[key] = { ...prev, manual_block: true };
  }

  const prevStart = addDays(startDate, -WINDOW_DAYS);
  const nextStart = addDays(startDate, WINDOW_DAYS);

  return (
    <div className="space-y-6 max-w-6xl">
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Calendar</h1>
          <p className="text-sm text-neutral-600 mt-1">
            {startDate} → {addDays(endDate, -1)} · click an empty cell to block it
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href={`/dashboard/calendar?start=${prevStart}`}
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            ← Prev
          </Link>
          <Link
            href="/dashboard/calendar"
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            Today
          </Link>
          <Link
            href={`/dashboard/calendar?start=${nextStart}`}
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            Next →
          </Link>
        </div>
      </div>

      <div className="flex items-center gap-4 text-xs text-neutral-500 flex-wrap">
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-white border border-neutral-200" /> Open
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-amber-100 border border-amber-200" /> Some booked
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-neutral-900 border border-neutral-900" /> Fully booked
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-red-100 border border-red-200" /> Manual block
        </span>
      </div>

      {kennels.length === 0 ? (
        <div className="rounded-md border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-500">
          No active kennel types yet.{" "}
          <Link href="/dashboard/listing" className="underline">
            Add kennels
          </Link>
          .
        </div>
      ) : (
        <AvailabilityGrid kennels={kennels} startDate={startDate} days={WINDOW_DAYS} cells={cells} />
      )}
    </div>
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
git add web/app/dashboard/calendar/page.tsx web/components/availability-grid.tsx
git commit -m "feat(web): calendar page with 14-day availability grid"
```

---

## Task 7: Playwright E2E — accept a seeded booking

This test needs a `requested` booking in the DB. Since no owner-facing UI exists yet, we seed directly via psql from the test.

**Files:**
- Create: `web/e2e/accept-booking.spec.ts`

- [ ] **Step 1: Write E2E**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/accept-booking.spec.ts`:
```ts
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

function psql(sql: string): string {
  const url = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  // -A: unaligned; -t: tuples only; -c: command
  return execSync(`psql "${url}" -A -t -c ${JSON.stringify(sql)}`, { encoding: "utf8" }).trim();
}

test("business admin accepts a seeded booking request", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `accept-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const businessName = `Accept E2E ${suffix}`;
  const slug = `accept-e2e-${suffix}`;

  // 1. Sign up + onboard via the UI (so we get a real auth.users row + business)
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(`Accept E2E ${suffix}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Accept St");
  await page.getByLabel("City").fill("KL");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // 2. Seed a kennel + owner + booking via psql (bypass RLS as postgres)
  const businessId = psql(`SELECT id FROM businesses WHERE slug = '${slug}';`);
  const listingId = psql(`SELECT id FROM listings WHERE business_id = '${businessId}';`);

  const ownerEmail = `owner-accept-${suffix}@petbnb.test`;
  const ownerId = "aaaaaaaa-bbbb-cccc-dddd-" + suffix.padEnd(12, "0").slice(0, 12);

  const kennelId = psql(`
    INSERT INTO kennel_types (listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
    VALUES ('${listingId}', 'E2E Suite', 'dog', 'small', 4, 80, 100)
    RETURNING id;
  `);

  psql(`
    INSERT INTO auth.users (id, email) VALUES ('${ownerId}', '${ownerEmail}');
    INSERT INTO user_profiles (id, display_name, primary_role) VALUES ('${ownerId}', 'Test Owner ${suffix}', 'owner');
  `);

  const petId = psql(`
    INSERT INTO pets (owner_id, name, species, breed, weight_kg)
    VALUES ('${ownerId}', 'TestPet-${suffix}', 'dog', 'Poodle', 8)
    RETURNING id;
  `);

  const bookingId = psql(`
    INSERT INTO bookings (
      owner_id, business_id, listing_id, kennel_type_id,
      check_in, check_out, nights, subtotal_myr, status, payment_deadline
    ) VALUES (
      '${ownerId}', '${businessId}', '${listingId}', '${kennelId}',
      '2027-05-10', '2027-05-12', 2, 160, 'requested', now() + interval '24 hours'
    ) RETURNING id;
  `);
  psql(`INSERT INTO booking_pets (booking_id, pet_id) VALUES ('${bookingId}', '${petId}');`);

  // 3. Reload inbox — the seeded request should appear
  await page.reload();
  await expect(page.getByText(`TestPet-${suffix}`)).toBeVisible();
  await expect(page.getByText(`Test Owner ${suffix}`)).toBeVisible();

  // 4. Accept it
  await page.getByRole("button", { name: /^Accept$/ }).click();

  // 5. Verify DB transitioned to accepted
  await expect.poll(
    () => psql(`SELECT status FROM bookings WHERE id = '${bookingId}';`),
    { timeout: 10_000, intervals: [500] },
  ).toBe("accepted");

  // 6. The card should be gone (no longer in pending list)
  await expect(page.getByText(`TestPet-${suffix}`)).not.toBeVisible();
});
```

- [ ] **Step 2: Run the full Playwright suite**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm exec playwright test
```
Expected: 4 tests passing (onboarding + kyc-upload + listing-editor + accept-booking).

If the accept test fails, STOP and report BLOCKED with:
- The Playwright failure output
- The DB state: `psql -c "SELECT id, status FROM bookings WHERE id = '<the-booking-id>';"` from the test output
- Any server-action error surfaced in the Next.js dev log

- [ ] **Step 3: Verify Phase 0 still green**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
./supabase/scripts/verify-phase0.sh
```
Expected: 74 pgTAP assertions passing; verify-phase0 green.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/e2e/accept-booking.spec.ts
git commit -m "test(web): Playwright E2E for accepting a seeded booking request"
```

---

## Task 8: README + Phase 1 complete handoff

**Files:**
- Modify: `web/README.md`
- Modify: `PetBnB/README.md`

- [ ] **Step 1: Append to `web/README.md`**

Read current `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`. Append after the existing "Listing editor flow (Phase 1c)" / "Known limitations" sections:

```markdown

## Inbox + calendar flow (Phase 1d)

1. `/dashboard/inbox` is the landing page after sign-in. Server component fetches bookings in `requested` status for the caller's business, joins pets + owner profile + cert-snapshot presence, renders `<BookingRequestCard>` per row. A `<InboxKpiStrip>` at the top shows pending count, today check-in, today check-out, and this-week business-payout revenue.
2. Accept / Decline buttons call the Phase 0 RPCs `accept_booking` / `decline_booking` via server actions in `app/dashboard/inbox/actions.ts`. Client components use `router.refresh()` after success.
3. `/dashboard/calendar` renders a 14-day kennel × date grid. URL param `?start=YYYY-MM-DD` drives the window; Prev / Today / Next links navigate by week.
4. Cell colors: white = open, amber = some bookings, dark = fully booked, red = manual block. Clicking an empty cell toggles a `manual_block` row in `availability_overrides`.

## Cross-user RLS for inbox

Phase 1d added two SELECT policies so business admins can render their customers' info:
- `pets_business_read` — a business_member can SELECT any pet linked via `booking_pets` to a booking at their business.
- `user_profiles_business_read` — a business_member can SELECT the profile of any user with a booking at their business.

Both are join-based — scoped correctly but runtime cost scales with the number of bookings. If this becomes a hotspot, consider denormalising `business_ids uuid[]` onto `pets` and maintaining it via trigger.

## Phase 1 complete

All four Phase 1 slices (a/b/c/d) are shipped. The business dashboard is functionally whole. Next up: Phase 2 — iOS owner app (SwiftUI), which reuses Court Booking POC patterns and consumes this backend.
```

- [ ] **Step 2: Update root `PetBnB/README.md`**

In the "Status" section, change `- [ ] Phase 1d — Calendar / availability grid + real Inbox` to `- [x] **Phase 1d** — Calendar + real inbox` and update the wrap to mark Phase 1 complete overall (add a summary line after the Phase 1 bullets, e.g. `**Phase 1 (business dashboard) — complete.**`).

- [ ] **Step 3: Final acceptance**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
./supabase/scripts/verify-phase0.sh
cd web && pnpm build
pnpm exec playwright test
```
All four must succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/README.md README.md
git commit -m "docs: Phase 1d README and Phase 1 complete handoff"
```

---

## Phase 1d complete — final checklist

- [ ] `git log --oneline | head -15` shows 8 new commits on top of Phase 1c (69 total).
- [ ] `supabase test db` — 74 assertions passing (68 + 6 new).
- [ ] `cd web && pnpm build` — no type errors.
- [ ] `pnpm exec playwright test` — 4 passing.
- [ ] Manual smoke: seed a requested booking via psql, visit `/dashboard/inbox`, accept it. Then visit `/dashboard/calendar`, click a cell, verify it flips to red.
- [ ] No credentials committed: `git log -p 04628c1..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

After Phase 1d, consider planning **Phase 2 — iOS owner app**. The booking-request, payment, and status-transition patterns from Court Booking POC can be reused.
