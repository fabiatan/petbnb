# PetBnB Phase 1c — Listing Editor + Kennel CRUD + Photo Management

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build out the `/dashboard/listing` page so a business admin can edit their listing (description, amenities, house rules, cancellation policy), manage a photo gallery (upload/reorder/remove), and do full CRUD on kennel types. After 1c, a business has a complete, realistic listing — everything the spec §9 "Listing" route specifies, minus the availability calendar (that's Phase 1d).

**Architecture:** Public-read / member-write `listing-photos` Supabase Storage bucket with path-scoped RLS (same pattern as 1b's `kyc-documents` but with a public SELECT policy since Phase 5 public pages need direct image URLs). Listing info + kennel CRUD goes through server actions that update `listings.*` and `kennel_types.*` via the authenticated Supabase client (existing RLS from Phase 0's `008_rls_policies.sql` already scopes both tables to business members). Soft delete on kennels (`active = false`) preserves historical bookings. No client-side Drizzle queries yet — supabase-js throughout.

**Tech Stack (unchanged from 1a/1b):**
- Next.js 16 App Router (server components + server actions)
- Tailwind + shadcn/ui (adding: Dialog, Select, Textarea, Switch, Badge)
- Supabase Storage via `@supabase/ssr`
- pgTAP for listing-photos Storage RLS test
- Playwright for E2E

**Spec references:** design spec §9 (business dashboard — Listing route)
**Phase 1b handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`

**Scope in this slice:**
- `listing-photos` public Storage bucket with write-scoped RLS
- Listing info fields: description, amenities[], house_rules, cancellation_policy preset
- Photo gallery: upload, reorder (up/down buttons — keep it simple), remove, max 12 photos per listing, max 5 MiB per photo, JPEG/PNG/WebP
- Kennel CRUD: add, edit, soft-deactivate (set `active = false`)
- Server actions for everything
- pgTAP for Storage RLS
- Playwright E2E: upload 2 photos, create a kennel, edit kennel price

**Out of scope (deferred):**
- Drag-and-drop photo reorder — Phase 5+ polish; up/down arrow buttons work fine for MVP
- In-browser photo cropping / editing — Phase 5+
- Amenities from a curated taxonomy — 1c ships free-form text array; picker UI can come later
- Rich text editor for description — plain textarea only
- Availability grid / calendar — Phase 1d
- Kennel hard delete — not offered; soft delete preserves historical bookings and is enough for MVP
- Per-kennel peak-date preview — defer
- Kennel "active" filter on the list page — always show all, just visually dim the inactive ones

**Phase 1c success criteria:**
1. A verified business can edit listing description + house rules + cancellation policy; changes persist on page reload.
2. Business can upload up to 12 photos in JPEG/PNG/WebP, ≤ 5 MiB each. Photos display as thumbnails with up/down/remove buttons. Order persists.
3. Business can add a kennel type with all Phase 0 fields (name, species, size, capacity, base/peak prices, instant-book flag, description).
4. Business can edit an existing kennel's fields; changes persist.
5. Business can deactivate a kennel; it shows as inactive but historical bookings are unaffected.
6. pgTAP Storage RLS test proves business B cannot write to business A's listing-photos path.
7. Playwright E2E passes end-to-end: sign up → onboard → /dashboard/listing → upload 2 photos → create a kennel → edit its price.
8. `supabase test db` continues passing all prior assertions + new Storage RLS assertions.
9. `cd web && pnpm build` clean.

---

## File structure

```
PetBnB/
├── supabase/
│   ├── migrations/
│   │   └── 015_listing_photos_storage.sql    (NEW)
│   └── tests/
│       └── 012_listing_photos_rls.sql        (NEW)
└── web/
    ├── app/
    │   └── dashboard/
    │       └── listing/
    │           ├── page.tsx                   (REPLACES 1a stub)
    │           └── actions.ts                  (NEW — all server actions)
    ├── components/
    │   ├── listing-info-form.tsx              (NEW)
    │   ├── listing-photo-gallery.tsx          (NEW)
    │   ├── kennel-list.tsx                    (NEW)
    │   └── kennel-editor-dialog.tsx           (NEW)
    ├── lib/
    │   └── listing.ts                         (NEW — constants, validators)
    └── e2e/
        └── listing-editor.spec.ts             (NEW)
```

---

## Task 1: Storage bucket + RLS migration

**Files:**
- Create: `supabase/migrations/015_listing_photos_storage.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/015_listing_photos_storage.sql`:
```sql
-- Listing photo storage.
-- Public-read (so the public SEO web app in Phase 5 can render img src URLs
-- directly without signed URL issuance); business-member-write for INSERT/UPDATE/DELETE.
-- Path convention: businesses/{business_id}/listing/{unique-filename}

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'listing-photos',
  'listing-photos',
  true,                                         -- public-read
  5242880,                                      -- 5 MiB per file
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Public SELECT (anyone, including anon, can read listing photos).
-- Without this, the public bucket flag alone isn't enough on some Supabase
-- versions — the policy is what actually grants anon read.
DROP POLICY IF EXISTS "listing_photos_public_read" ON storage.objects;
CREATE POLICY "listing_photos_public_read"
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (bucket_id = 'listing-photos');

-- INSERT / UPDATE / DELETE: business members only, scoped by business_id in path.
-- Same foldername/regex pattern as 014_kyc_storage.sql — see that file for rationale.
DROP POLICY IF EXISTS "listing_photos_member_write" ON storage.objects;
CREATE POLICY "listing_photos_member_write"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'listing-photos'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 3
  AND (storage.foldername(name))[1] = 'businesses'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND (storage.foldername(name))[3] = 'listing'
  AND is_business_member((storage.foldername(name))[2]::uuid)
)
WITH CHECK (
  bucket_id = 'listing-photos'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 3
  AND (storage.foldername(name))[1] = 'businesses'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND (storage.foldername(name))[3] = 'listing'
  AND is_business_member((storage.foldername(name))[2]::uuid)
);
```

- [ ] **Step 2: Apply**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase db reset
```

- [ ] **Step 3: Verify bucket + policies**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT id, public, file_size_limit FROM storage.buckets WHERE id = 'listing-photos';"
```
Expected: `listing-photos | t | 5242880`

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT policyname, cmd FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'listing_photos%' ORDER BY policyname;"
```
Expected: 2 rows — `listing_photos_member_write | ALL` and `listing_photos_public_read | SELECT`.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/015_listing_photos_storage.sql
git commit -m "feat(db): listing-photos Storage bucket (public read, member write)"
```

---

## Task 2: pgTAP test for listing-photos Storage RLS

**Files:**
- Create: `supabase/tests/012_listing_photos_rls.sql`

- [ ] **Step 1: Write test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/012_listing_photos_rls.sql`:
```sql
BEGIN;
SELECT plan(5);

-- Seed: two businesses + a non-member random user
INSERT INTO auth.users (id, email) VALUES
  ('11111111-0000-0000-0000-000000000a01', 'alice-p@t'),
  ('11111111-0000-0000-0000-000000000a02', 'bob-p@t'),
  ('11111111-0000-0000-0000-000000000a03', 'noone-p@t');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('11111111-0000-0000-0000-000000000a01', 'Alice', 'business_admin'),
  ('11111111-0000-0000-0000-000000000a02', 'Bob',   'business_admin'),
  ('11111111-0000-0000-0000-000000000a03', 'No One', 'owner');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('cccccccc-0000-0000-0000-000000000001', 'Biz A-p', 'biz-a-p', '1', 'KL', 'WP', 'verified', 'active'),
  ('cccccccc-0000-0000-0000-000000000002', 'Biz B-p', 'biz-b-p', '1', 'KL', 'WP', 'verified', 'active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('cccccccc-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000a01'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000a02');

-- Seed files directly as postgres (bypasses RLS)
INSERT INTO storage.objects (bucket_id, name, owner, metadata) VALUES
  ('listing-photos',
   'businesses/cccccccc-0000-0000-0000-000000000001/listing/a.jpg',
   '11111111-0000-0000-0000-000000000a01',
   '{"mimetype":"image/jpeg"}'::jsonb),
  ('listing-photos',
   'businesses/cccccccc-0000-0000-0000-000000000002/listing/b.jpg',
   '11111111-0000-0000-0000-000000000a02',
   '{"mimetype":"image/jpeg"}'::jsonb);

-- 1. anonymous SELECT sees both files (public bucket)
RESET role;
SET LOCAL role = 'anon';
SELECT is(
  (SELECT count(*)::int FROM storage.objects WHERE bucket_id='listing-photos'),
  2, 'anon can read all listing photos');

-- 2. Alice (Biz A admin) can read both (public) but write only hers
RESET role;
SET LOCAL request.jwt.claim.sub = '11111111-0000-0000-0000-000000000a01';
SET LOCAL role = 'authenticated';
SELECT is(
  (SELECT count(*)::int FROM storage.objects WHERE bucket_id='listing-photos'),
  2, 'Alice reads both photos via public policy');

-- 3. Alice can insert into her own path
SELECT lives_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('listing-photos',
             'businesses/cccccccc-0000-0000-0000-000000000001/listing/a2.jpg',
             '11111111-0000-0000-0000-000000000a01',
             '{"mimetype":"image/jpeg"}'::jsonb) $$,
  'Alice can insert into her business path');

-- 4. Alice CANNOT insert into Biz B path
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('listing-photos',
             'businesses/cccccccc-0000-0000-0000-000000000002/listing/hack.jpg',
             '11111111-0000-0000-0000-000000000a01',
             '{"mimetype":"image/jpeg"}'::jsonb) $$,
  '42501', NULL,
  'Alice cannot insert into Biz B path');

-- 5. Non-member (noone) CANNOT insert anywhere
RESET role;
SET LOCAL request.jwt.claim.sub = '11111111-0000-0000-0000-000000000a03';
SET LOCAL role = 'authenticated';
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('listing-photos',
             'businesses/cccccccc-0000-0000-0000-000000000001/listing/hack.jpg',
             '11111111-0000-0000-0000-000000000a03',
             '{"mimetype":"image/jpeg"}'::jsonb) $$,
  '42501', NULL,
  'non-member cannot insert');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
```
Expected: 68 assertions passing (63 prior + 5 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/012_listing_photos_rls.sql
git commit -m "test(db): listing-photos Storage RLS (public read, member write)"
```

---

## Task 3: Install shadcn primitives needed for forms/dialogs

**Files:**
- Adds shadcn primitives to `web/components/ui/`

- [ ] **Step 1: Install**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm dlx shadcn@latest add dialog textarea select switch badge --yes
```

- [ ] **Step 2: Build check**

```bash
pnpm build
```
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/
git commit -m "feat(web): add shadcn primitives (dialog, textarea, select, switch, badge)"
```

---

## Task 4: Shared listing constants + types (`lib/listing.ts`)

**Files:**
- Create: `web/lib/listing.ts`

- [ ] **Step 1: Write file**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/listing.ts`:
```ts
// Constants, types, and validators for listings and kennels.
// Framework-agnostic (no React, no Next imports).

export const CANCELLATION_POLICIES = ["flexible", "moderate", "strict"] as const;
export type CancellationPolicy = (typeof CANCELLATION_POLICIES)[number];
export const CANCELLATION_POLICY_LABELS: Record<CancellationPolicy, string> = {
  flexible: "Flexible — full refund up to 48h before check-in",
  moderate: "Moderate — full refund up to 7 days; then 50%",
  strict: "Strict — 50% up to 7 days; then 0%",
};

export const SPECIES_ACCEPTED = ["dog", "cat", "both"] as const;
export type SpeciesAccepted = (typeof SPECIES_ACCEPTED)[number];
export const SPECIES_ACCEPTED_LABELS: Record<SpeciesAccepted, string> = {
  dog: "Dogs only",
  cat: "Cats only",
  both: "Dogs and cats",
};

export const SIZE_RANGES = ["small", "medium", "large"] as const;
export type SizeRange = (typeof SIZE_RANGES)[number];
export const SIZE_RANGE_LABELS: Record<SizeRange, string> = {
  small: "Small (≤ 10 kg)",
  medium: "Medium (10–25 kg)",
  large: "Large (> 25 kg)",
};

export const MAX_PHOTOS = 12;
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MiB
export const ALLOWED_PHOTO_MIME = ["image/jpeg", "image/png", "image/webp"] as const;

export const MAX_AMENITIES = 20;
export const MAX_AMENITY_LENGTH = 40;

// Server-side input validation for a kennel. Returns { ok: true, value } or
// { ok: false, error }. Used in server actions.
export type KennelFormInput = {
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: number;
  peak_price_myr: number;
  instant_book: boolean;
  description: string | null;
};

export function validateKennelInput(
  raw: Record<string, unknown>,
): { ok: true; value: KennelFormInput } | { ok: false; error: string } {
  const name = String(raw.name ?? "").trim();
  if (!name) return { ok: false, error: "Name is required" };
  if (name.length > 80) return { ok: false, error: "Name too long (max 80)" };

  const species = String(raw.species_accepted ?? "");
  if (!(SPECIES_ACCEPTED as readonly string[]).includes(species)) {
    return { ok: false, error: "Invalid species" };
  }

  const size = String(raw.size_range ?? "");
  if (!(SIZE_RANGES as readonly string[]).includes(size)) {
    return { ok: false, error: "Invalid size range" };
  }

  const capacity = Number(raw.capacity);
  if (!Number.isInteger(capacity) || capacity < 1 || capacity > 500) {
    return { ok: false, error: "Capacity must be an integer between 1 and 500" };
  }

  const base = Number(raw.base_price_myr);
  if (!Number.isFinite(base) || base < 0 || base > 99999) {
    return { ok: false, error: "Base price must be between 0 and 99999" };
  }
  const peak = Number(raw.peak_price_myr);
  if (!Number.isFinite(peak) || peak < 0 || peak > 99999) {
    return { ok: false, error: "Peak price must be between 0 and 99999" };
  }
  if (peak < base) {
    return { ok: false, error: "Peak price cannot be less than base price" };
  }

  const instant = raw.instant_book === "on" || raw.instant_book === true || raw.instant_book === "true";

  const description = raw.description ? String(raw.description).trim().slice(0, 500) : null;

  return {
    ok: true,
    value: {
      name,
      species_accepted: species as SpeciesAccepted,
      size_range: size as SizeRange,
      capacity,
      base_price_myr: base,
      peak_price_myr: peak,
      instant_book: instant,
      description,
    },
  };
}

export function listingPhotoPath(businessId: string, uniqueId: string, filename: string): string {
  const safeName = filename.replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 100);
  return `businesses/${businessId}/listing/${uniqueId}_${safeName}`;
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/lib/listing.ts
git commit -m "feat(web): listing/kennel constants + input validators"
```

---

## Task 5: All listing server actions (info, photos, kennels)

Single file with all the mutations for the listing page.

**Files:**
- Create: `web/app/dashboard/listing/actions.ts`

- [ ] **Step 1: Write file**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/listing/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";
import {
  ALLOWED_PHOTO_MIME,
  CANCELLATION_POLICIES,
  CancellationPolicy,
  listingPhotoPath,
  MAX_AMENITIES,
  MAX_AMENITY_LENGTH,
  MAX_PHOTO_BYTES,
  MAX_PHOTOS,
  validateKennelInput,
} from "@/lib/listing";

export type ActionState = { error?: string; ok?: true };

async function resolveContext(): Promise<
  | { kind: "ok"; businessId: string; listingId: string; userId: string }
  | { kind: "err"; error: string }
> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { kind: "err", error: "Not authenticated" };

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) return { kind: "err", error: "No business membership" };

  const { data: listing } = await supabase
    .from("listings")
    .select("id")
    .eq("business_id", membership.business_id)
    .limit(1)
    .maybeSingle();
  if (!listing) return { kind: "err", error: "Listing not found for business" };

  return {
    kind: "ok",
    businessId: membership.business_id,
    listingId: listing.id,
    userId: user.id,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing info
// ─────────────────────────────────────────────────────────────────────────────

export async function updateListingInfoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const description = String(formData.get("description") ?? "").trim().slice(0, 2000) || null;
  const houseRules = String(formData.get("house_rules") ?? "").trim().slice(0, 2000) || null;
  const policyRaw = String(formData.get("cancellation_policy") ?? "moderate");
  if (!(CANCELLATION_POLICIES as readonly string[]).includes(policyRaw)) {
    return { error: "Invalid cancellation policy" };
  }
  const cancellationPolicy = policyRaw as CancellationPolicy;

  const amenitiesRaw = String(formData.get("amenities") ?? "").trim();
  const amenities = amenitiesRaw
    ? amenitiesRaw
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a.length > 0 && a.length <= MAX_AMENITY_LENGTH)
        .slice(0, MAX_AMENITIES)
    : [];

  const supabase = await createClient();
  const { error } = await supabase
    .from("listings")
    .update({
      description,
      house_rules: houseRules,
      cancellation_policy: cancellationPolicy,
      amenities,
    })
    .eq("id", ctx.listingId);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Photos
// ─────────────────────────────────────────────────────────────────────────────

async function readCurrentPhotos(listingId: string): Promise<string[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("listings")
    .select("photos")
    .eq("id", listingId)
    .single();
  return (data?.photos as string[] | null) ?? [];
}

export async function uploadListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const files = formData.getAll("files").filter((f): f is File => f instanceof File && f.size > 0);
  if (files.length === 0) return { error: "Choose at least one photo" };

  const current = await readCurrentPhotos(ctx.listingId);
  if (current.length + files.length > MAX_PHOTOS) {
    return { error: `Max ${MAX_PHOTOS} photos (you have ${current.length})` };
  }

  for (const f of files) {
    if (f.size > MAX_PHOTO_BYTES) return { error: `${f.name} exceeds 5 MB` };
    if (!(ALLOWED_PHOTO_MIME as readonly string[]).includes(f.type)) {
      return { error: `${f.name}: only JPEG/PNG/WebP` };
    }
  }

  const supabase = await createClient();
  const newPaths: string[] = [];
  for (const f of files) {
    const path = listingPhotoPath(ctx.businessId, randomUUID(), f.name);
    const { error } = await supabase.storage
      .from("listing-photos")
      .upload(path, f, { contentType: f.type, upsert: false });
    if (error) return { error: `Upload failed: ${error.message}` };
    newPaths.push(path);
  }

  const nextPhotos = [...current, ...newPaths];
  const { error: updErr } = await supabase
    .from("listings")
    .update({ photos: nextPhotos })
    .eq("id", ctx.listingId);
  if (updErr) return { error: updErr.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function removeListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const path = String(formData.get("path") ?? "");
  if (!path) return { error: "path required" };

  const current = await readCurrentPhotos(ctx.listingId);
  if (!current.includes(path)) return { error: "Photo not found on this listing" };

  const supabase = await createClient();
  const { error: remErr } = await supabase.storage.from("listing-photos").remove([path]);
  if (remErr) return { error: `Storage remove failed: ${remErr.message}` };

  const nextPhotos = current.filter((p) => p !== path);
  const { error: updErr } = await supabase
    .from("listings")
    .update({ photos: nextPhotos })
    .eq("id", ctx.listingId);
  if (updErr) return { error: updErr.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function reorderListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const path = String(formData.get("path") ?? "");
  const direction = String(formData.get("direction") ?? "");
  if (!path || (direction !== "up" && direction !== "down")) {
    return { error: "Invalid reorder request" };
  }

  const current = await readCurrentPhotos(ctx.listingId);
  const idx = current.indexOf(path);
  if (idx < 0) return { error: "Photo not found" };
  const targetIdx = direction === "up" ? idx - 1 : idx + 1;
  if (targetIdx < 0 || targetIdx >= current.length) return { ok: true }; // no-op at edge

  const next = [...current];
  [next[idx], next[targetIdx]] = [next[targetIdx], next[idx]];

  const supabase = await createClient();
  const { error } = await supabase
    .from("listings")
    .update({ photos: next })
    .eq("id", ctx.listingId);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Kennels
// ─────────────────────────────────────────────────────────────────────────────

export async function createKennelAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const raw = Object.fromEntries(formData.entries());
  const parsed = validateKennelInput(raw);
  if (!parsed.ok) return { error: parsed.error };

  const supabase = await createClient();
  const { error } = await supabase.from("kennel_types").insert({
    listing_id: ctx.listingId,
    ...parsed.value,
  });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function updateKennelAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const id = String(formData.get("id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(id)) return { error: "Invalid kennel id" };

  const raw = Object.fromEntries(formData.entries());
  const parsed = validateKennelInput(raw);
  if (!parsed.ok) return { error: parsed.error };

  const supabase = await createClient();

  // Guard: the kennel must belong to this business's listing
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("listing_id")
    .eq("id", id)
    .maybeSingle();
  if (!kennel || kennel.listing_id !== ctx.listingId) {
    return { error: "Kennel not found or not yours" };
  }

  const { error } = await supabase
    .from("kennel_types")
    .update(parsed.value)
    .eq("id", id);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function toggleKennelActiveAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const id = String(formData.get("id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(id)) return { error: "Invalid kennel id" };

  const supabase = await createClient();
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("listing_id, active")
    .eq("id", id)
    .maybeSingle();
  if (!kennel || kennel.listing_id !== ctx.listingId) {
    return { error: "Kennel not found or not yours" };
  }

  const { error } = await supabase
    .from("kennel_types")
    .update({ active: !kennel.active })
    .eq("id", id);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/app/dashboard/listing/actions.ts
git commit -m "feat(web): listing info, photo, and kennel server actions"
```

---

## Task 6: Listing info form component

**Files:**
- Create: `web/components/listing-info-form.tsx`

- [ ] **Step 1: Write component**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/listing-info-form.tsx`:
```tsx
"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  CANCELLATION_POLICIES,
  CANCELLATION_POLICY_LABELS,
  CancellationPolicy,
} from "@/lib/listing";
import { updateListingInfoAction, type ActionState } from "@/app/dashboard/listing/actions";

export function ListingInfoForm({
  initialDescription,
  initialHouseRules,
  initialAmenities,
  initialCancellationPolicy,
}: {
  initialDescription: string | null;
  initialHouseRules: string | null;
  initialAmenities: string[];
  initialCancellationPolicy: CancellationPolicy;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(
    updateListingInfoAction,
    {},
  );

  return (
    <form action={action} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          name="description"
          rows={5}
          defaultValue={initialDescription ?? ""}
          placeholder="Air-conditioned kennels, daily walks, live CCTV for owners…"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="amenities">Amenities (comma-separated)</Label>
        <Input
          id="amenities"
          name="amenities"
          defaultValue={initialAmenities.join(", ")}
          placeholder="air_con, daily_walks, cctv"
        />
        <p className="text-xs text-neutral-500">Up to 20 items, 40 characters each.</p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="house_rules">House rules</Label>
        <Textarea
          id="house_rules"
          name="house_rules"
          rows={3}
          defaultValue={initialHouseRules ?? ""}
          placeholder="No aggressive dogs. Vaccination required."
        />
      </div>

      <div className="space-y-2">
        <Label>Cancellation policy</Label>
        <Select name="cancellation_policy" defaultValue={initialCancellationPolicy}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {CANCELLATION_POLICIES.map((p) => (
              <SelectItem key={p} value={p}>
                {CANCELLATION_POLICY_LABELS[p]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      {state.ok ? <p className="text-sm text-emerald-600">Saved.</p> : null}

      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save listing info"}
      </Button>
    </form>
  );
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/components/listing-info-form.tsx
git commit -m "feat(web): listing info form component"
```

---

## Task 7: Photo gallery component

**Files:**
- Create: `web/components/listing-photo-gallery.tsx`

- [ ] **Step 1: Write component**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/listing-photo-gallery.tsx`:
```tsx
"use client";

import { useActionState } from "react";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { ALLOWED_PHOTO_MIME, MAX_PHOTOS } from "@/lib/listing";
import {
  removeListingPhotoAction,
  reorderListingPhotoAction,
  uploadListingPhotoAction,
  type ActionState,
} from "@/app/dashboard/listing/actions";

export function ListingPhotoGallery({
  photoPaths,
  publicUrls,
}: {
  photoPaths: string[];
  publicUrls: Record<string, string>; // path -> publicUrl
}) {
  const [uploadState, uploadAction, uploadPending] = useActionState<ActionState, FormData>(
    uploadListingPhotoAction,
    {},
  );
  const [removeState, removeAction, removePending] = useActionState<ActionState, FormData>(
    removeListingPhotoAction,
    {},
  );
  const [reorderState, reorderAction, reorderPending] = useActionState<ActionState, FormData>(
    reorderListingPhotoAction,
    {},
  );

  const errorMsg = uploadState.error ?? removeState.error ?? reorderState.error;
  const canUpload = photoPaths.length < MAX_PHOTOS;

  return (
    <div className="space-y-4">
      {canUpload ? (
        <form action={uploadAction} className="flex items-center gap-2">
          <input
            type="file"
            name="files"
            multiple
            accept={ALLOWED_PHOTO_MIME.join(",")}
            required
            className="text-xs file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:text-white file:px-3 file:py-1.5 file:text-xs file:cursor-pointer"
          />
          <Button type="submit" size="sm" disabled={uploadPending}>
            {uploadPending ? "Uploading…" : "Upload"}
          </Button>
          <span className="text-xs text-neutral-500">
            {photoPaths.length}/{MAX_PHOTOS} · JPEG/PNG/WebP, ≤ 5 MB each
          </span>
        </form>
      ) : (
        <p className="text-xs text-neutral-500">Maximum {MAX_PHOTOS} photos reached. Remove one to upload more.</p>
      )}

      {errorMsg ? <p className="text-sm text-red-600">{errorMsg}</p> : null}

      {photoPaths.length === 0 ? (
        <div className="rounded-md border border-dashed border-neutral-300 px-4 py-8 text-center text-sm text-neutral-500">
          No photos yet.
        </div>
      ) : (
        <ul className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {photoPaths.map((path, idx) => {
            const url = publicUrls[path] ?? "";
            return (
              <li key={path} className="relative group border border-neutral-200 rounded-md overflow-hidden bg-neutral-50">
                <div className="relative aspect-video">
                  {url ? (
                    <Image
                      src={url}
                      alt={`Listing photo ${idx + 1}`}
                      fill
                      className="object-cover"
                      sizes="(max-width: 768px) 50vw, 33vw"
                      unoptimized
                    />
                  ) : null}
                </div>
                <div className="flex items-center gap-1 p-2 bg-white border-t border-neutral-200">
                  <form action={reorderAction}>
                    <input type="hidden" name="path" value={path} />
                    <input type="hidden" name="direction" value="up" />
                    <Button size="sm" variant="outline" type="submit" disabled={reorderPending || idx === 0}>
                      ↑
                    </Button>
                  </form>
                  <form action={reorderAction}>
                    <input type="hidden" name="path" value={path} />
                    <input type="hidden" name="direction" value="down" />
                    <Button
                      size="sm"
                      variant="outline"
                      type="submit"
                      disabled={reorderPending || idx === photoPaths.length - 1}
                    >
                      ↓
                    </Button>
                  </form>
                  <form action={removeAction} className="ml-auto">
                    <input type="hidden" name="path" value={path} />
                    <Button size="sm" variant="outline" type="submit" disabled={removePending}>
                      Remove
                    </Button>
                  </form>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/components/listing-photo-gallery.tsx
git commit -m "feat(web): listing photo gallery component"
```

---

## Task 8: Kennel editor dialog + list components

Two components — one table showing all kennels, one dialog for add/edit.

**Files:**
- Create: `web/components/kennel-editor-dialog.tsx`
- Create: `web/components/kennel-list.tsx`

- [ ] **Step 1: Write `kennel-editor-dialog.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/kennel-editor-dialog.tsx`:
```tsx
"use client";

import { useActionState, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  SIZE_RANGES,
  SIZE_RANGE_LABELS,
  SPECIES_ACCEPTED,
  SPECIES_ACCEPTED_LABELS,
  SizeRange,
  SpeciesAccepted,
} from "@/lib/listing";
import {
  createKennelAction,
  updateKennelAction,
  type ActionState,
} from "@/app/dashboard/listing/actions";

export type KennelInitial = {
  id?: string;
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: string;
  peak_price_myr: string;
  instant_book: boolean;
  description: string;
};

export function KennelEditorDialog({
  trigger,
  title,
  initial,
  mode,
}: {
  trigger: React.ReactNode;
  title: string;
  initial: KennelInitial;
  mode: "create" | "edit";
}) {
  const [open, setOpen] = useState(false);
  const action = mode === "create" ? createKennelAction : updateKennelAction;
  const [state, submit, pending] = useActionState<ActionState, FormData>(action, {});

  // Close the dialog when the action succeeds
  if (state.ok && open) {
    queueMicrotask(() => setOpen(false));
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {mode === "create"
              ? "Add a new kennel type to your listing."
              : "Edit this kennel's details. Changes apply to future bookings only."}
          </DialogDescription>
        </DialogHeader>

        <form action={submit} className="space-y-4">
          {mode === "edit" && initial.id ? (
            <input type="hidden" name="id" value={initial.id} />
          ) : null}

          <div className="space-y-2">
            <Label htmlFor="name">Name</Label>
            <Input id="name" name="name" required defaultValue={initial.name} placeholder="Small Dog Suite" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Species accepted</Label>
              <Select name="species_accepted" defaultValue={initial.species_accepted}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {SPECIES_ACCEPTED.map((s) => (
                    <SelectItem key={s} value={s}>{SPECIES_ACCEPTED_LABELS[s]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Size range</Label>
              <Select name="size_range" defaultValue={initial.size_range}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {SIZE_RANGES.map((s) => (
                    <SelectItem key={s} value={s}>{SIZE_RANGE_LABELS[s]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label htmlFor="capacity">Capacity</Label>
              <Input id="capacity" name="capacity" type="number" min={1} max={500} required defaultValue={initial.capacity} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="base_price_myr">Base / night (MYR)</Label>
              <Input id="base_price_myr" name="base_price_myr" type="number" step="0.01" min={0} required defaultValue={initial.base_price_myr} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="peak_price_myr">Peak / night (MYR)</Label>
              <Input id="peak_price_myr" name="peak_price_myr" type="number" step="0.01" min={0} required defaultValue={initial.peak_price_myr} />
            </div>
          </div>

          <div className="flex items-center justify-between rounded-md border border-neutral-200 px-3 py-2">
            <div>
              <Label htmlFor="instant_book" className="font-medium">Instant book</Label>
              <p className="text-xs text-neutral-500">Owners can book and pay immediately without manual approval.</p>
            </div>
            <Switch id="instant_book" name="instant_book" defaultChecked={initial.instant_book} />
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Description</Label>
            <Textarea id="description" name="description" rows={3} defaultValue={initial.description} maxLength={500} />
          </div>

          {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={pending}>
              {pending ? "Saving…" : mode === "create" ? "Create kennel" : "Save"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 2: Write `kennel-list.tsx`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/kennel-list.tsx`:
```tsx
"use client";

import { useActionState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  KennelEditorDialog,
  type KennelInitial,
} from "@/components/kennel-editor-dialog";
import { SIZE_RANGE_LABELS, SPECIES_ACCEPTED_LABELS, SizeRange, SpeciesAccepted } from "@/lib/listing";
import { toggleKennelActiveAction, type ActionState } from "@/app/dashboard/listing/actions";

export type KennelRow = {
  id: string;
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: string;
  peak_price_myr: string;
  instant_book: boolean;
  description: string | null;
  active: boolean;
};

function toInitial(row: KennelRow): KennelInitial {
  return {
    id: row.id,
    name: row.name,
    species_accepted: row.species_accepted,
    size_range: row.size_range,
    capacity: row.capacity,
    base_price_myr: row.base_price_myr,
    peak_price_myr: row.peak_price_myr,
    instant_book: row.instant_book,
    description: row.description ?? "",
  };
}

export function KennelList({ kennels }: { kennels: KennelRow[] }) {
  const blankInitial: KennelInitial = {
    name: "",
    species_accepted: "dog",
    size_range: "small",
    capacity: 1,
    base_price_myr: "0",
    peak_price_myr: "0",
    instant_book: false,
    description: "",
  };
  const [toggleState, toggleAction, togglePending] = useActionState<ActionState, FormData>(
    toggleKennelActiveAction,
    {},
  );

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-neutral-600">
          {kennels.length === 0 ? "No kennels yet." : `${kennels.length} kennel type${kennels.length === 1 ? "" : "s"}`}
        </p>
        <KennelEditorDialog
          trigger={<Button size="sm">Add kennel</Button>}
          title="Add kennel"
          initial={blankInitial}
          mode="create"
        />
      </div>

      {toggleState.error ? <p className="text-sm text-red-600">{toggleState.error}</p> : null}

      {kennels.map((k) => (
        <Card key={k.id} className={k.active ? "border-neutral-200" : "border-neutral-200 opacity-60"}>
          <CardContent className="p-4 flex items-start gap-4 flex-wrap">
            <div className="flex-1 min-w-[240px]">
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="font-semibold">{k.name}</h3>
                {k.instant_book ? <Badge className="bg-emerald-600">Instant book</Badge> : null}
                {!k.active ? <Badge variant="outline">Inactive</Badge> : null}
              </div>
              <p className="text-xs text-neutral-500 mt-1">
                {SPECIES_ACCEPTED_LABELS[k.species_accepted]} · {SIZE_RANGE_LABELS[k.size_range]} · capacity {k.capacity}
              </p>
              <p className="text-xs text-neutral-500 mt-0.5">
                Base RM{Number(k.base_price_myr).toFixed(2)} · Peak RM{Number(k.peak_price_myr).toFixed(2)}
              </p>
              {k.description ? (
                <p className="text-xs text-neutral-600 mt-2">{k.description}</p>
              ) : null}
            </div>
            <div className="flex gap-2">
              <KennelEditorDialog
                trigger={<Button size="sm" variant="outline">Edit</Button>}
                title={`Edit ${k.name}`}
                initial={toInitial(k)}
                mode="edit"
              />
              <form action={toggleAction}>
                <input type="hidden" name="id" value={k.id} />
                <Button size="sm" variant="outline" type="submit" disabled={togglePending}>
                  {k.active ? "Deactivate" : "Activate"}
                </Button>
              </form>
            </div>
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
git add web/components/kennel-editor-dialog.tsx web/components/kennel-list.tsx
git commit -m "feat(web): kennel list + editor dialog components"
```

---

## Task 9: `/dashboard/listing` page assembly

Wire everything together. Replaces the Phase 1a stub.

**Files:**
- Modify: `web/app/dashboard/listing/page.tsx`
- Modify: `web/next.config.ts` (allow Supabase hostnames for `next/image`)

- [ ] **Step 1: Allow Supabase hostnames in Next.js image config**

Read current `/Users/fabian/CodingProject/Primary/PetBnB/web/next.config.ts`. Merge the following `images` block into the existing config (preserve any other options the scaffold put there):

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      // Local Supabase
      { protocol: "http", hostname: "127.0.0.1", port: "54321", pathname: "/storage/v1/object/public/**" },
      // Production Supabase (placeholder — configure per-project in Phase 5)
      { protocol: "https", hostname: "*.supabase.co", pathname: "/storage/v1/object/public/**" },
    ],
  },
};

export default nextConfig;
```

If the existing config already has other fields, preserve them and add `images` alongside.

- [ ] **Step 2: Overwrite `app/dashboard/listing/page.tsx`**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/listing/page.tsx` with:
```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Separator } from "@/components/ui/separator";
import { ListingInfoForm } from "@/components/listing-info-form";
import { ListingPhotoGallery } from "@/components/listing-photo-gallery";
import { KennelList, type KennelRow } from "@/components/kennel-list";
import { CancellationPolicy } from "@/lib/listing";

export default async function ListingPage() {
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

  const { data: listing } = await supabase
    .from("listings")
    .select("id, description, amenities, house_rules, cancellation_policy, photos")
    .eq("business_id", membership.business_id)
    .single();

  const photoPaths: string[] = (listing?.photos as string[] | null) ?? [];
  const publicUrls: Record<string, string> = {};
  for (const p of photoPaths) {
    const { data } = supabase.storage.from("listing-photos").getPublicUrl(p);
    publicUrls[p] = data.publicUrl;
  }

  const { data: kennelsRaw } = await supabase
    .from("kennel_types")
    .select("id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book, description, active")
    .eq("listing_id", listing?.id ?? "")
    .order("created_at", { ascending: true });
  const kennels: KennelRow[] = (kennelsRaw ?? []) as KennelRow[];

  return (
    <div className="max-w-4xl space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Listing</h1>
        <p className="text-sm text-neutral-600 mt-1">
          Everything owners see when they view your business.
        </p>
      </div>

      <section>
        <h2 className="text-lg font-semibold">Info</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">Description, amenities, house rules, cancellation policy.</p>
        <ListingInfoForm
          initialDescription={(listing?.description as string | null) ?? null}
          initialHouseRules={(listing?.house_rules as string | null) ?? null}
          initialAmenities={(listing?.amenities as string[] | null) ?? []}
          initialCancellationPolicy={
            (listing?.cancellation_policy as CancellationPolicy | null) ?? "moderate"
          }
        />
      </section>

      <Separator />

      <section>
        <h2 className="text-lg font-semibold">Photos</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">Up to 12 photos. First photo is the hero image.</p>
        <ListingPhotoGallery photoPaths={photoPaths} publicUrls={publicUrls} />
      </section>

      <Separator />

      <section>
        <h2 className="text-lg font-semibold">Kennel types</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">
          The bookable units inside your listing. Each kennel type has its own pricing, capacity, and acceptance rules.
        </p>
        <KennelList kennels={kennels} />
      </section>
    </div>
  );
}
```

- [ ] **Step 3: Build + manual smoke test**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
pnpm dev
```

Open http://localhost:3000 in a browser. Sign up as a new user, onboard a business, then visit `/dashboard/listing`. Verify:
- Listing info form renders with defaults.
- Photos section shows "No photos yet." and an upload form.
- Kennel types section shows "No kennels yet." + an "Add kennel" button.
- Click "Add kennel" — dialog opens. Fill in test values (Name: Small Dog Suite, Species: Dog, Size: Small, Capacity: 4, Base: 80, Peak: 100). Submit — dialog closes, kennel row appears.
- Click "Edit" — dialog opens pre-populated. Change Base to 90, Save. The card updates.
- Click "Deactivate" — card dims and the button becomes "Activate".

Stop the dev server.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/app/dashboard/listing/page.tsx web/next.config.ts
git commit -m "feat(web): /dashboard/listing page wired to info + photos + kennels"
```

---

## Task 10: Playwright E2E — listing editor flow

**Files:**
- Create: `web/e2e/listing-editor.spec.ts`
- Create: `web/e2e/fixtures/photo.jpg` (a tiny JPEG)

- [ ] **Step 1: Create tiny JPEG fixture**

A minimal valid JPEG is ~125 bytes. Run from `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
mkdir -p web/e2e/fixtures
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.'"'"' ",#\x1c\x1c(7),01444\x1f'"'"'9=82<.342\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b\xff\xc4\x00\xb5\x10\x00\x02\x01\x03\x03\x02\x04\x03\x05\x05\x04\x04\x00\x00\x01}\x01\x02\x03\x00\x04\x11\x05\x12!1A\x06\x13Qa\x07"q\x142\x81\x91\xa1\x08#B\xb1\xc1\x15R\xd1\xf0$3br\x82\t\n\x16\x17\x18\x19\x1a%&'"'"'()*456789:CDEFGHIJSTUVWXYZcdefghijstuvwxyz\x83\x84\x85\x86\x87\x88\x89\x8a\x92\x93\x94\x95\x96\x97\x98\x99\x9a\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xfb\xd7\xff\xd9' > web/e2e/fixtures/photo.jpg
file web/e2e/fixtures/photo.jpg
```
Expected: `web/e2e/fixtures/photo.jpg: JPEG image data, JFIF standard 1.01`.

- [ ] **Step 2: Write E2E test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/listing-editor.spec.ts`:
```ts
import { test, expect } from "@playwright/test";
import path from "node:path";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("listing editor: photo upload + kennel CRUD", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `listing-e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const businessName = `Listing E2E ${suffix}`;
  const slug = `listing-e2e-${suffix}`;

  // Sign up + onboard
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(`Listing E2E ${suffix}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Listing St");
  await page.getByLabel("City").fill("KL");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // Navigate to listing editor
  await page.getByRole("link", { name: "Listing", exact: true }).click();
  await expect(page).toHaveURL(/\/dashboard\/listing$/);
  await expect(page.getByRole("heading", { name: "Listing", exact: true })).toBeVisible();

  // Upload 2 photos
  const fixturePath = path.join(__dirname, "fixtures", "photo.jpg");
  const fileInput = page.locator('input[type=file][name="files"]');
  await fileInput.setInputFiles([fixturePath, fixturePath]);
  await page.getByRole("button", { name: /^Upload$/ }).click();
  await expect(page.locator("ul li")).toHaveCount(2, { timeout: 15_000 });

  // Create a kennel
  await page.getByRole("button", { name: /Add kennel/i }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await dialog.getByLabel("Name").fill("E2E Suite");
  await dialog.getByLabel("Capacity").fill("3");
  await dialog.getByLabel("Base / night (MYR)").fill("80");
  await dialog.getByLabel("Peak / night (MYR)").fill("100");
  await dialog.getByRole("button", { name: /Create kennel/i }).click();
  await expect(page.getByText("E2E Suite")).toBeVisible({ timeout: 10_000 });

  // Edit the kennel price
  await page.getByRole("button", { name: /^Edit$/ }).first().click();
  const editDialog = page.getByRole("dialog");
  await expect(editDialog).toBeVisible();
  const baseInput = editDialog.getByLabel("Base / night (MYR)");
  await baseInput.fill("90");
  await editDialog.getByRole("button", { name: /^Save$/ }).click();
  await expect(page.getByText(/RM90\.00/)).toBeVisible({ timeout: 10_000 });
});
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm exec playwright test
```
Expected: 3 tests passing (onboarding + kyc-upload + listing-editor).

If the listing-editor test fails, STOP and report BLOCKED with the Playwright failure output + the relevant state in psql (`SELECT * FROM listings WHERE business_id IN (SELECT id FROM businesses WHERE slug LIKE 'listing-e2e-%');`).

- [ ] **Step 4: Verify Phase 0–1b still green**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
./supabase/scripts/verify-phase0.sh
```
Expected: 68 pgTAP passing; verify-phase0 green.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/e2e/
git commit -m "test(web): Playwright E2E for listing editor"
```

---

## Task 11: README + handoff

**Files:**
- Modify: `web/README.md`
- Modify: `PetBnB/README.md`

- [ ] **Step 1: Append "Listing editor flow" to `web/README.md`**

Read current `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`. Append after the existing "KYC upload flow" / "Storage RLS" sections:

```markdown

## Listing editor flow (Phase 1c)

1. `/dashboard/listing` loads the business's listing row + kennel types.
2. Three sections: Info (description, amenities, house rules, cancellation policy), Photos (up to 12, with up/down reorder + remove), Kennels (add/edit/toggle-active dialog).
3. Server actions in `app/dashboard/listing/actions.ts` handle all mutations and call `revalidatePath` so the page updates after each action.
4. Photos live in the public `listing-photos` Storage bucket at path `businesses/{business_id}/listing/{uuid}_{filename}`. Storage RLS makes SELECT public (any user/anon can view) but INSERT/UPDATE/DELETE business-member-only.
5. Kennel deactivation is soft: we set `active = false` instead of deleting so historical bookings' FK references remain valid.

## Known limitations (to address in later phases)

- Photo reorder uses up/down buttons, not drag-and-drop. 5+
- Amenities are free-form strings — no taxonomy. Could become a picker later.
- Description is plain textarea, no rich text.
- Kennel hard delete is never offered. If you want to clean up, deactivate and filter.
```

- [ ] **Step 2: Update root `PetBnB/README.md` status**

In the "Status" section, change `- [ ] Phase 1c — Listing editor + kennel CRUD + photo management` to `- [x] **Phase 1c** — Listing editor + kennel CRUD + photos`.

- [ ] **Step 3: Final acceptance**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
./supabase/scripts/verify-phase0.sh
cd web && pnpm build
pnpm exec playwright test
```
All must succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/README.md README.md
git commit -m "docs: Phase 1c README and listing editor handoff"
```

---

## Phase 1c complete — final checklist

- [ ] `git log --oneline | head -15` shows 11 new commits on top of Phase 1b (61 total).
- [ ] `supabase test db` — 68 assertions passing.
- [ ] `cd web && pnpm build` — no type errors.
- [ ] `pnpm exec playwright test` — 3 passing.
- [ ] Manual smoke: visit `/dashboard/listing`, upload a photo, create a kennel, edit it, toggle active.
- [ ] `listing-photos` bucket and both its policies exist: `SELECT count(*) FROM pg_policies WHERE policyname LIKE 'listing_photos%';` returns 2.
- [ ] No credentials committed: `git log -p f01dab5..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

Then plan Phase 1d (calendar / availability + real inbox).
