# PetBnB Phase 1b — KYC Document Upload + Supabase Storage

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Business admins can upload 4 KYC documents (SSM cert, business license, proof of premises, owner IC) to a private Supabase Storage bucket scoped by business. The dashboard shows a status banner ("upload pending" / "awaiting review" / hidden) driven off `businesses.kyc_status` + `kyc_documents` jsonb.

**Architecture:** Add one migration that creates the `kyc-documents` Storage bucket and the Storage RLS policy that scopes file access to business members (by business_id in the path). Add one server action `uploadKycDocument(docType, formData)` that validates file size + MIME, uploads via the authenticated Supabase client (RLS enforces business membership), and PATCHes the business's `kyc_documents` jsonb. One remove action for replacements. All UI lives under `/dashboard/settings/kyc`. Platform-admin approval (flipping `kyc_status` to `verified`) continues to happen externally in Supabase Studio — there's no internal admin UI in 1b.

**Tech Stack (unchanged from 1a):**
- Next.js 16 App Router + React 19 (server components + server actions)
- Supabase Storage via `@supabase/ssr` server client
- Tailwind + shadcn/ui (Button, Input, Card)
- pgTAP for Storage RLS test
- Playwright for E2E

**Spec reference:** `/Users/fabian/CodingProject/Primary/docs/superpowers/specs/2026-04-22-petbnb-owner-sitter-booking-design.md` (§3 O2 "Medium KYC")
**Phase 1a handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`

**Scope in this slice:**
- Private `kyc-documents` Storage bucket with path-scoped RLS
- Server action: upload KYC doc (4 doc types, size/MIME validation)
- Server action: remove/replace KYC doc
- `/dashboard/settings/kyc` page with 4 document cards
- KYC status banner in the dashboard layout
- pgTAP test for Storage RLS cross-business blocking
- Playwright E2E: upload a test PDF, verify kyc_documents jsonb updated
- `/dashboard/settings/page.tsx` becomes an overview with a KYC link card (replaces the 1a stub)

**Out of scope (explicitly deferred):**
- Platform-admin verification UI — still Supabase Studio only
- Automated doc verification (SSM API lookup, MyKad OCR) — out of Phase 1 entirely
- Document rejection / resubmission workflow — Phase 5+
- File virus scanning — Phase 5+ via an Edge Function hook
- In-product audit log of KYC events — Phase 5+
- Multi-branch / multi-premises KYC — MVP assumes one premises per business
- Downloading KYC docs back as PDFs from the UI — uploads are write-only from the business side; they see filenames and upload dates but cannot re-download (they already have the originals; this cuts a security surface)

**Phase 1b success criteria:**
1. Fresh onboarded business shows a banner: "Upload KYC documents to activate your listing" with a link to `/dashboard/settings/kyc`.
2. Business admin can upload one SSM cert PDF → page refreshes → the SSM card shows "Uploaded <filename> · <timestamp> · Remove".
3. Uploading all 4 required docs → banner flips to "KYC under review. We'll email you within 48 hours."
4. A platform_admin flips `kyc_status` → `verified` in Supabase Studio → banner disappears on next page load.
5. pgTAP test proves business B's admin cannot read or write business A's files under `kyc-documents`.
6. Playwright E2E passes sign-up → onboarding → KYC upload → verify jsonb updated.
7. `supabase test db` continues passing all prior assertions (58 Phase 0/1a + new Storage RLS assertions).
8. `cd web && pnpm build` and `pnpm exec playwright test` both succeed.

---

## File structure

Phase 1b adds new files plus modifies 3 existing ones:

```
PetBnB/
├── supabase/
│   ├── migrations/
│   │   └── 014_kyc_storage.sql            (NEW — bucket + Storage RLS)
│   └── tests/
│       └── 011_kyc_storage_rls.sql        (NEW — Storage cross-business RLS)
└── web/
    ├── app/
    │   └── dashboard/
    │       ├── layout.tsx                  (MODIFIED — render KycBanner)
    │       └── settings/
    │           ├── page.tsx                (MODIFIED — overview w/ KYC card, replaces stub)
    │           └── kyc/
    │               ├── page.tsx            (NEW — 4 doc cards + upload form)
    │               └── actions.ts          (NEW — upload/remove server actions)
    ├── components/
    │   ├── kyc-banner.tsx                  (NEW — dashboard banner)
    │   └── kyc-document-card.tsx           (NEW — single doc card with upload/replace)
    ├── lib/
    │   └── kyc.ts                          (NEW — doc types + shared validation)
    └── e2e/
        └── kyc-upload.spec.ts              (NEW — Playwright E2E for upload)
```

---

## Task 1: Storage bucket + RLS migration

Create the `kyc-documents` bucket and the RLS policy on `storage.objects` that scopes access by business_id in the path.

**Files:**
- Create: `supabase/migrations/014_kyc_storage.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/014_kyc_storage.sql`:
```sql
-- KYC document storage: private bucket, scoped by business_id in the path.
-- Path convention: businesses/{business_id}/{doc_type}/{filename}
-- doc_type ∈ {ssm_cert, business_license, proof_of_premises, owner_ic}

-- Create the bucket (idempotent — re-apply safe)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'kyc-documents',
  'kyc-documents',
  false,
  10485760,                                   -- 10 MiB per file
  ARRAY['application/pdf','image/jpeg','image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Policy: business members can read/write files scoped to their business path.
-- storage.foldername(name) returns the path components as a text[], e.g.
-- for "businesses/abc.../ssm_cert/file.pdf" it returns {businesses, abc..., ssm_cert}.
-- We require (a) path starts with 'businesses', (b) second segment is a UUID,
-- (c) caller is a member of that business.
DROP POLICY IF EXISTS "kyc_business_members_all" ON storage.objects;
CREATE POLICY "kyc_business_members_all"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'kyc-documents'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'businesses'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND is_business_member((storage.foldername(name))[2]::uuid)
)
WITH CHECK (
  bucket_id = 'kyc-documents'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'businesses'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND is_business_member((storage.foldername(name))[2]::uuid)
);

-- Defensive: ensure RLS is enabled on storage.objects (it is by default on
-- modern Supabase; this line is idempotent).
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
```

- [ ] **Step 2: Apply migration**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase db reset
```
Expected: finishes without errors.

- [ ] **Step 3: Verify bucket exists**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT id, public, file_size_limit FROM storage.buckets WHERE id = 'kyc-documents';"
```
Expected: one row — `kyc-documents | f | 10485760`.

- [ ] **Step 4: Verify policy exists**

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT policyname FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='kyc_business_members_all';"
```
Expected: one row.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/014_kyc_storage.sql
git commit -m "feat(db): kyc-documents Storage bucket with path-scoped RLS"
```

---

## Task 2: pgTAP test — Storage RLS cross-business isolation

Prove that business B's admin cannot read or write under business A's path.

**Files:**
- Create: `supabase/tests/011_kyc_storage_rls.sql`

- [ ] **Step 1: Write test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/011_kyc_storage_rls.sql`:
```sql
BEGIN;
SELECT plan(5);

-- Two auth users + profiles + two businesses + memberships
INSERT INTO auth.users (id, email) VALUES
  ('11111111-2222-3333-4444-000000000001', 'alice@kyc-a.test'),
  ('11111111-2222-3333-4444-000000000002', 'bob@kyc-b.test');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('11111111-2222-3333-4444-000000000001', 'Alice', 'business_admin'),
  ('11111111-2222-3333-4444-000000000002', 'Bob',   'business_admin');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('aaaaaaaa-bbbb-cccc-dddd-000000000001', 'Biz A', 'biz-a-kyc', '1 A', 'KL', 'WP', 'pending', 'active'),
  ('aaaaaaaa-bbbb-cccc-dddd-000000000002', 'Biz B', 'biz-b-kyc', '1 B', 'KL', 'WP', 'pending', 'active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('aaaaaaaa-bbbb-cccc-dddd-000000000001', '11111111-2222-3333-4444-000000000001'),
  ('aaaaaaaa-bbbb-cccc-dddd-000000000002', '11111111-2222-3333-4444-000000000002');

-- Seed two storage.objects rows directly (bypass RLS as postgres role)
INSERT INTO storage.objects (bucket_id, name, owner, metadata)
VALUES
  ('kyc-documents',
   'businesses/aaaaaaaa-bbbb-cccc-dddd-000000000001/ssm_cert/a.pdf',
   '11111111-2222-3333-4444-000000000001',
   '{"mimetype":"application/pdf"}'::jsonb),
  ('kyc-documents',
   'businesses/aaaaaaaa-bbbb-cccc-dddd-000000000002/ssm_cert/b.pdf',
   '11111111-2222-3333-4444-000000000002',
   '{"mimetype":"application/pdf"}'::jsonb);

-- Impersonate Alice (Biz A)
SET LOCAL request.jwt.claim.sub = '11111111-2222-3333-4444-000000000001';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='kyc-documents'),
  1, 'Alice sees only her business file');

SELECT is(
  (SELECT count(*)::int FROM storage.objects
    WHERE bucket_id='kyc-documents'
      AND name LIKE 'businesses/aaaaaaaa-bbbb-cccc-dddd-000000000002/%'),
  0, 'Alice cannot see Biz B file by path filter');

-- Impersonate Bob (Biz B)
RESET role;
SET LOCAL request.jwt.claim.sub = '11111111-2222-3333-4444-000000000002';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='kyc-documents'),
  1, 'Bob sees only his business file');

-- Impersonate a random authenticated user not in any business
INSERT INTO auth.users (id, email) VALUES ('99999999-0000-0000-0000-000000000001', 'noone@t');
INSERT INTO user_profiles (id, display_name) VALUES ('99999999-0000-0000-0000-000000000001', 'No One');
RESET role;
SET LOCAL request.jwt.claim.sub = '99999999-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='kyc-documents'),
  0, 'non-member sees 0 files');

-- Non-member INSERT is blocked (simulate upload attempt)
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES (
       'kyc-documents',
       'businesses/aaaaaaaa-bbbb-cccc-dddd-000000000001/ssm_cert/hack.pdf',
       '99999999-0000-0000-0000-000000000001',
       '{"mimetype":"application/pdf"}'::jsonb) $$,
  '42501',   -- insufficient_privilege (RLS rejection)
  'non-member cannot upload into Biz A folder');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run tests**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
```
Expected: 63 assertions pass (58 prior + 5 new).

If the `throws_ok` assertion fails with a different SQLSTATE, adjust the expected SQLSTATE to whatever RLS actually returns on this Supabase version — run the same INSERT manually with `SET role = authenticated` to find out. Report any deviation.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/011_kyc_storage_rls.sql
git commit -m "test(db): Storage RLS blocks cross-business KYC access"
```

---

## Task 3: Shared KYC constants + types (`lib/kyc.ts`)

Document types, allowed MIME types, and the jsonb shape.

**Files:**
- Create: `web/lib/kyc.ts`

- [ ] **Step 1: Write file**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/lib/kyc.ts`:
```ts
// Shared KYC constants used by server actions, UI, and validation.
// Keep this file framework-agnostic — no React, no Next imports — so it can
// be pulled into Edge Functions or workers later without pulling in a renderer.

export const KYC_DOC_TYPES = [
  "ssm_cert",
  "business_license",
  "proof_of_premises",
  "owner_ic",
] as const;

export type KycDocType = (typeof KYC_DOC_TYPES)[number];

export const KYC_DOC_LABELS: Record<KycDocType, string> = {
  ssm_cert: "SSM registration certificate",
  business_license: "Business operating license",
  proof_of_premises: "Proof of premises (tenancy / ownership)",
  owner_ic: "Owner / director MyKad (IC)",
};

export const KYC_DOC_DESCRIPTIONS: Record<KycDocType, string> = {
  ssm_cert: "Form D/E from SSM, or Super Form for Sdn Bhd.",
  business_license:
    "Local council license authorising your pet boarding operation.",
  proof_of_premises:
    "Tenancy agreement, utility bill, or title deed showing your registered address.",
  owner_ic:
    "Front + back photo of the owner's MyKad, merged into a single PDF or image.",
};

export const KYC_MAX_FILE_BYTES = 10 * 1024 * 1024; // 10 MiB

export const KYC_ALLOWED_MIME = [
  "application/pdf",
  "image/jpeg",
  "image/png",
] as const;

// Shape of businesses.kyc_documents jsonb.
// Each doc, when uploaded, carries: storage path, upload timestamp,
// original filename, content type, and byte size.
export type KycDocEntry = {
  path: string;          // e.g. "businesses/<uuid>/ssm_cert/cert.pdf"
  uploaded_at: string;   // ISO 8601
  filename: string;      // original (client-supplied) filename
  content_type: string;  // verified MIME
  size_bytes: number;
};

export type KycDocuments = Partial<Record<KycDocType, KycDocEntry>>;

export function isKycComplete(docs: KycDocuments): boolean {
  return KYC_DOC_TYPES.every((t) => Boolean(docs[t]?.path));
}

export function storagePath(businessId: string, docType: KycDocType, filename: string): string {
  // Normalise filename to avoid path traversal / weird chars.
  const safeName = filename.replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 120);
  return `businesses/${businessId}/${docType}/${safeName}`;
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm build
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/lib/kyc.ts
git commit -m "feat(web): KYC doc types, labels, validation constants"
```

---

## Task 4: Upload + remove server actions

Server actions that validate, upload to Storage, and update `businesses.kyc_documents` jsonb.

**Files:**
- Create: `web/app/dashboard/settings/kyc/actions.ts`

- [ ] **Step 1: Write actions**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/settings/kyc/actions.ts`:
```ts
"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  KYC_ALLOWED_MIME,
  KYC_DOC_TYPES,
  KYC_MAX_FILE_BYTES,
  KycDocEntry,
  KycDocType,
  KycDocuments,
  storagePath,
} from "@/lib/kyc";

export type KycActionState = { error?: string; uploadedDocType?: KycDocType };

async function resolveBusinessId(): Promise<
  | { kind: "ok"; businessId: string; userId: string }
  | { kind: "err"; error: string }
> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { kind: "err", error: "Not authenticated" };

  const { data: membership, error } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (error) return { kind: "err", error: error.message };
  if (!membership) return { kind: "err", error: "No business membership" };

  return { kind: "ok", businessId: membership.business_id, userId: user.id };
}

export async function uploadKycDocumentAction(
  _prev: KycActionState,
  formData: FormData,
): Promise<KycActionState> {
  const docTypeRaw = String(formData.get("docType") ?? "");
  const file = formData.get("file");

  if (!KYC_DOC_TYPES.includes(docTypeRaw as KycDocType)) {
    return { error: `Invalid document type: ${docTypeRaw}` };
  }
  const docType = docTypeRaw as KycDocType;

  if (!(file instanceof File) || file.size === 0) {
    return { error: "Please choose a file." };
  }
  if (file.size > KYC_MAX_FILE_BYTES) {
    return { error: "File exceeds 10 MB." };
  }
  if (!(KYC_ALLOWED_MIME as readonly string[]).includes(file.type)) {
    return { error: "Only PDF, JPEG, or PNG files are accepted." };
  }

  const ctx = await resolveBusinessId();
  if (ctx.kind === "err") return { error: ctx.error };

  const supabase = await createClient();
  const path = storagePath(ctx.businessId, docType, file.name);

  // Remove any existing file at the same docType (replace semantics)
  const { data: biz, error: bizReadError } = await supabase
    .from("businesses")
    .select("kyc_documents")
    .eq("id", ctx.businessId)
    .single();
  if (bizReadError) return { error: bizReadError.message };

  const docs = (biz?.kyc_documents ?? {}) as KycDocuments;
  const prior = docs[docType];
  if (prior?.path && prior.path !== path) {
    const { error: removeErr } = await supabase.storage
      .from("kyc-documents")
      .remove([prior.path]);
    if (removeErr) return { error: `Failed to remove prior file: ${removeErr.message}` };
  }

  const { error: uploadErr } = await supabase.storage
    .from("kyc-documents")
    .upload(path, file, { upsert: true, contentType: file.type });
  if (uploadErr) return { error: `Upload failed: ${uploadErr.message}` };

  const entry: KycDocEntry = {
    path,
    uploaded_at: new Date().toISOString(),
    filename: file.name,
    content_type: file.type,
    size_bytes: file.size,
  };
  const nextDocs: KycDocuments = { ...docs, [docType]: entry };

  const { error: updateErr } = await supabase
    .from("businesses")
    .update({ kyc_documents: nextDocs })
    .eq("id", ctx.businessId);
  if (updateErr) return { error: `Metadata update failed: ${updateErr.message}` };

  revalidatePath("/dashboard/settings/kyc");
  revalidatePath("/dashboard", "layout");
  return { uploadedDocType: docType };
}

export async function removeKycDocumentAction(
  _prev: KycActionState,
  formData: FormData,
): Promise<KycActionState> {
  const docTypeRaw = String(formData.get("docType") ?? "");
  if (!KYC_DOC_TYPES.includes(docTypeRaw as KycDocType)) {
    return { error: `Invalid document type: ${docTypeRaw}` };
  }
  const docType = docTypeRaw as KycDocType;

  const ctx = await resolveBusinessId();
  if (ctx.kind === "err") return { error: ctx.error };

  const supabase = await createClient();

  const { data: biz, error: bizReadError } = await supabase
    .from("businesses")
    .select("kyc_documents")
    .eq("id", ctx.businessId)
    .single();
  if (bizReadError) return { error: bizReadError.message };

  const docs = (biz?.kyc_documents ?? {}) as KycDocuments;
  const prior = docs[docType];
  if (!prior) return {}; // nothing to remove; silent no-op

  const { error: removeErr } = await supabase.storage
    .from("kyc-documents")
    .remove([prior.path]);
  if (removeErr) return { error: `Storage remove failed: ${removeErr.message}` };

  const nextDocs: KycDocuments = { ...docs };
  delete nextDocs[docType];

  const { error: updateErr } = await supabase
    .from("businesses")
    .update({ kyc_documents: nextDocs })
    .eq("id", ctx.businessId);
  if (updateErr) return { error: `Metadata update failed: ${updateErr.message}` };

  revalidatePath("/dashboard/settings/kyc");
  revalidatePath("/dashboard", "layout");
  return {};
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
git add web/app/dashboard/settings/kyc/actions.ts
git commit -m "feat(web): KYC upload + remove server actions"
```

---

## Task 5: KYC document card component

A single card for one doc type, with upload/replace/remove controls.

**Files:**
- Create: `web/components/kyc-document-card.tsx`

- [ ] **Step 1: Write component**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/kyc-document-card.tsx`:
```tsx
"use client";

import { useActionState, useRef } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  KYC_ALLOWED_MIME,
  KYC_DOC_DESCRIPTIONS,
  KYC_DOC_LABELS,
  KycDocEntry,
  KycDocType,
} from "@/lib/kyc";
import {
  removeKycDocumentAction,
  uploadKycDocumentAction,
  type KycActionState,
} from "@/app/dashboard/settings/kyc/actions";

function formatBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString("en-MY", { dateStyle: "medium", timeStyle: "short" });
}

export function KycDocumentCard({
  docType,
  entry,
}: {
  docType: KycDocType;
  entry: KycDocEntry | undefined;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [uploadState, uploadAction, uploadPending] = useActionState<KycActionState, FormData>(
    uploadKycDocumentAction,
    {},
  );
  const [removeState, removeAction, removePending] = useActionState<KycActionState, FormData>(
    removeKycDocumentAction,
    {},
  );

  const hasFile = !!entry;

  return (
    <Card className="border-neutral-200">
      <CardContent className="p-5 space-y-3">
        <div>
          <h3 className="font-semibold text-base">{KYC_DOC_LABELS[docType]}</h3>
          <p className="text-xs text-neutral-500 mt-1">{KYC_DOC_DESCRIPTIONS[docType]}</p>
        </div>

        {hasFile ? (
          <div className="rounded-md bg-emerald-50 border border-emerald-200 px-3 py-2 text-xs">
            <div className="font-medium text-emerald-900">{entry.filename}</div>
            <div className="text-emerald-700 mt-0.5">
              {formatBytes(entry.size_bytes)} · uploaded {formatDate(entry.uploaded_at)}
            </div>
          </div>
        ) : (
          <div className="rounded-md border border-dashed border-neutral-300 px-3 py-2 text-xs text-neutral-500">
            No file uploaded yet.
          </div>
        )}

        <form
          ref={formRef}
          action={uploadAction}
          className="flex items-center gap-2 flex-wrap"
          encType="multipart/form-data"
        >
          <input type="hidden" name="docType" value={docType} />
          <input
            type="file"
            name="file"
            accept={KYC_ALLOWED_MIME.join(",")}
            required
            className="text-xs file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:text-white file:px-3 file:py-1.5 file:text-xs file:cursor-pointer"
          />
          <Button type="submit" size="sm" disabled={uploadPending}>
            {uploadPending ? "Uploading…" : hasFile ? "Replace" : "Upload"}
          </Button>
          {hasFile ? (
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={removePending}
              onClick={() => {
                const fd = new FormData();
                fd.append("docType", docType);
                removeAction(fd);
              }}
            >
              {removePending ? "Removing…" : "Remove"}
            </Button>
          ) : null}
        </form>

        {uploadState.error ? (
          <p className="text-xs text-red-600">{uploadState.error}</p>
        ) : null}
        {removeState.error ? (
          <p className="text-xs text-red-600">{removeState.error}</p>
        ) : null}
      </CardContent>
    </Card>
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
git add web/components/kyc-document-card.tsx
git commit -m "feat(web): KYC document card component"
```

---

## Task 6: KYC page + settings overview

Wire the 4 cards into a page, and make `/dashboard/settings` show an overview that links to KYC.

**Files:**
- Create: `web/app/dashboard/settings/kyc/page.tsx`
- Modify: `web/app/dashboard/settings/page.tsx` (replace the 1a stub)

- [ ] **Step 1: Write KYC page**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/settings/kyc/page.tsx`:
```tsx
import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { KYC_DOC_TYPES, KycDocuments, isKycComplete } from "@/lib/kyc";
import { KycDocumentCard } from "@/components/kyc-document-card";

export default async function KycPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id, businesses!inner(kyc_status, kyc_documents)")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const biz = membership.businesses as unknown as {
    kyc_status: "pending" | "verified" | "rejected";
    kyc_documents: KycDocuments | null;
  };
  const docs: KycDocuments = biz.kyc_documents ?? {};
  const complete = isKycComplete(docs);

  return (
    <div className="max-w-3xl">
      <div className="mb-2">
        <Link href="/dashboard/settings" className="text-xs text-neutral-500 hover:underline">
          ← Settings
        </Link>
      </div>
      <h1 className="text-2xl font-bold tracking-tight">KYC documents</h1>
      <p className="text-sm text-neutral-600 mt-1">
        Upload the four documents below so we can verify your business. You can replace a file at any time.
      </p>

      <div className="mt-6 space-y-4">
        {KYC_DOC_TYPES.map((docType) => (
          <KycDocumentCard key={docType} docType={docType} entry={docs[docType]} />
        ))}
      </div>

      <div className="mt-8 text-xs text-neutral-500">
        Status: <strong className="text-neutral-900">{biz.kyc_status}</strong>
        {complete && biz.kyc_status === "pending"
          ? " — all documents uploaded. Our team will review within 48 hours."
          : null}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Replace settings stub**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/settings/page.tsx`:
```tsx
import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";

export default function SettingsPage() {
  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-bold tracking-tight">Settings</h1>
      <p className="text-sm text-neutral-600 mt-1">Manage your business profile and verification documents.</p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <Link href="/dashboard/settings/kyc" className="group">
          <Card className="border-neutral-200 transition group-hover:border-neutral-900">
            <CardContent className="p-5">
              <h2 className="font-semibold">KYC documents</h2>
              <p className="text-xs text-neutral-500 mt-1">
                Upload SSM cert, business license, proof of premises, and owner MyKad.
              </p>
            </CardContent>
          </Card>
        </Link>

        <Card className="border-neutral-200 opacity-60">
          <CardContent className="p-5">
            <h2 className="font-semibold">Business profile</h2>
            <p className="text-xs text-neutral-500 mt-1">Coming later — edit address, description, photos.</p>
          </CardContent>
        </Card>
      </div>
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
git add web/app/dashboard/settings/
git commit -m "feat(web): KYC upload page and settings overview"
```

---

## Task 7: Dashboard KYC banner

Server component that pulls current `kyc_status` + `kyc_documents` and renders the banner.

**Files:**
- Create: `web/components/kyc-banner.tsx`
- Modify: `web/app/dashboard/layout.tsx` (render banner above main content)

- [ ] **Step 1: Write banner**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/components/kyc-banner.tsx`:
```tsx
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { isKycComplete, KycDocuments } from "@/lib/kyc";

export async function KycBanner() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: membership } = await supabase
    .from("business_members")
    .select("businesses!inner(kyc_status, kyc_documents)")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) return null;

  const biz = membership.businesses as unknown as {
    kyc_status: "pending" | "verified" | "rejected";
    kyc_documents: KycDocuments | null;
  };
  if (biz.kyc_status === "verified") return null;

  const docs = biz.kyc_documents ?? {};
  const complete = isKycComplete(docs);

  if (biz.kyc_status === "rejected") {
    return (
      <div className="border-b border-red-200 bg-red-50 px-6 py-3 text-sm flex items-center justify-between gap-4">
        <span className="text-red-900">
          <strong>KYC rejected.</strong> Please review notes and re-upload documents.
        </span>
        <Link
          href="/dashboard/settings/kyc"
          className="text-red-900 underline font-medium whitespace-nowrap"
        >
          Update documents
        </Link>
      </div>
    );
  }

  if (complete) {
    return (
      <div className="border-b border-amber-200 bg-amber-50 px-6 py-3 text-sm flex items-center gap-4">
        <span className="text-amber-900">
          <strong>KYC under review.</strong> We'll email you within 48 hours.
        </span>
      </div>
    );
  }

  return (
    <div className="border-b border-neutral-900 bg-neutral-900 text-white px-6 py-3 text-sm flex items-center justify-between gap-4">
      <span>
        <strong>Upload KYC documents</strong> to activate your listing.
      </span>
      <Link
        href="/dashboard/settings/kyc"
        className="underline font-medium whitespace-nowrap"
      >
        Upload now
      </Link>
    </div>
  );
}
```

- [ ] **Step 2: Render in dashboard layout**

Edit `/Users/fabian/CodingProject/Primary/PetBnB/web/app/dashboard/layout.tsx` — import `KycBanner` and render it above the `<main>` element. Replace the existing file with:

```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DashboardSidebar } from "@/components/dashboard-sidebar";
import { KycBanner } from "@/components/kyc-banner";

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
      <div className="flex-1 flex flex-col">
        <KycBanner />
        <main className="flex-1 p-6">{children}</main>
      </div>
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
git add web/components/kyc-banner.tsx web/app/dashboard/layout.tsx
git commit -m "feat(web): KYC status banner in dashboard layout"
```

---

## Task 8: Playwright E2E — upload a KYC doc

Automate the upload flow and verify `kyc_documents` jsonb is populated.

**Files:**
- Create: `web/e2e/kyc-upload.spec.ts`
- Create: `web/e2e/fixtures/sample.pdf` (a tiny valid PDF file)

- [ ] **Step 1: Create test PDF fixture**

Create a tiny valid PDF at `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/fixtures/sample.pdf`. The simplest way is a 1-page PDF with just a text string — write the raw bytes:

```bash
mkdir -p /Users/fabian/CodingProject/Primary/PetBnB/web/e2e/fixtures
cat > /Users/fabian/CodingProject/Primary/PetBnB/web/e2e/fixtures/sample.pdf << 'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj
4 0 obj<</Length 44>>stream
BT /F1 24 Tf 100 700 Td (PetBnB KYC test) Tj ET
endstream endobj
xref
0 5
0000000000 65535 f
0000000009 00000 n
0000000054 00000 n
0000000099 00000 n
0000000162 00000 n
trailer<</Size 5/Root 1 0 R>>
startxref
254
%%EOF
EOF
```

- [ ] **Step 2: Write E2E test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/web/e2e/kyc-upload.spec.ts`:
```ts
import { test, expect } from "@playwright/test";
import path from "node:path";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("upload KYC document appears in settings", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `kyc-e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const displayName = `KYC E2E ${suffix}`;
  const businessName = `KYC E2E Biz ${suffix}`;
  const slug = `kyc-e2e-${suffix}`;

  // Sign up + onboard
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(displayName);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Test Street");
  await page.getByLabel("City").fill("Kuala Lumpur");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // Banner should prompt for KYC upload
  await expect(page.getByText(/Upload KYC documents/i)).toBeVisible();

  // Navigate to the KYC page
  await page.getByRole("link", { name: /Upload now/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/settings\/kyc$/);
  await expect(page.getByRole("heading", { name: /KYC documents/i })).toBeVisible();

  // Upload the sample PDF into the SSM cert card (first card)
  const fixturePath = path.join(__dirname, "fixtures", "sample.pdf");
  const fileInput = page.locator("input[type=file]").first();
  await fileInput.setInputFiles(fixturePath);
  await page.getByRole("button", { name: /^Upload$/ }).first().click();

  // Wait for the "Replace" button to appear (indicates successful upload)
  await expect(page.getByRole("button", { name: /^Replace$/ }).first()).toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByText("sample.pdf").first()).toBeVisible();
});
```

- [ ] **Step 3: Run Playwright tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/web
pnpm exec playwright test
```
Expected: 2 passed (the existing `onboarding.spec.ts` plus the new `kyc-upload.spec.ts`).

If the test fails because the upload doesn't surface the replace button within the timeout, check: (a) the dev-server console logs for server-action errors, (b) `SELECT kyc_documents FROM businesses` in psql to see if the upload actually happened but the UI didn't refresh. Report BLOCKED with the specifics.

- [ ] **Step 4: Verify Phase 0 still green**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
./supabase/scripts/verify-phase0.sh
```
Expected: 63 pgTAP assertions pass (58 prior + 5 from Task 2); verify-phase0 succeeds.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add web/e2e/
git commit -m "test(web): Playwright E2E for KYC document upload"
```

---

## Task 9: README + handoff

Update status, document the KYC flow, note what 1c will build on.

**Files:**
- Modify: `web/README.md`
- Modify: `PetBnB/README.md`

- [ ] **Step 1: Update `web/README.md` status + flow**

Read current `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`. Append a new section after the existing "Auth flow" section:

```markdown

## KYC upload flow (Phase 1b)

1. New business signs up + onboards → lands on `/dashboard/inbox`.
2. Dashboard layout renders `<KycBanner>` — for any business with `kyc_status='pending'`, shows a prompt linking to `/dashboard/settings/kyc`.
3. `/dashboard/settings/kyc` renders 4 `<KycDocumentCard>`s — one per doc type. Each card has an upload input + server-action submit button.
4. Server action validates (≤ 10 MB, PDF/JPEG/PNG only), uploads to the `kyc-documents` Storage bucket at path `businesses/{business_id}/{doc_type}/{safe_filename}`, and PATCHes `businesses.kyc_documents` jsonb with a reference.
5. Once all 4 docs are uploaded, the banner flips to "KYC under review."
6. Platform admin manually flips `businesses.kyc_status` to `verified` in Supabase Studio (no internal admin UI in Phase 1b).

## Storage RLS

The `kyc-documents` bucket's RLS policy scopes read/write to business members by parsing the UUID in the path. See `supabase/migrations/014_kyc_storage.sql`. Cross-business access is proved blocked by `supabase/tests/011_kyc_storage_rls.sql`.
```

- [ ] **Step 2: Update root `PetBnB/README.md` status list**

In the "Status" section, change `- [ ] Phase 1b — KYC upload (Supabase Storage) and documents review` to `- [x] **Phase 1b** — KYC upload and documents review`.

- [ ] **Step 3: Final acceptance check**

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
git commit -m "docs: Phase 1b README and KYC handoff"
```

---

## Phase 1b complete — final checklist

- [ ] `git log --oneline | head -15` shows 9 new commits on top of Phase 1a's 41 (50 total).
- [ ] `supabase test db` — 63 assertions passing.
- [ ] `cd web && pnpm build` — no type errors.
- [ ] `pnpm exec playwright test` — 2 passing.
- [ ] Manual smoke test: sign up a fresh user, upload a PDF, banner flips from "Upload KYC" to one of the other states.
- [ ] Storage bucket exists: `psql -c "SELECT id FROM storage.buckets WHERE id='kyc-documents';"` returns one row.
- [ ] No new credentials committed: `git log -p f9f9eb8..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

Then plan Phase 1c (listing + kennel CRUD + photo management).
