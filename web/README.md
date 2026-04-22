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

## KYC upload flow (Phase 1b)

1. New business signs up + onboards → lands on `/dashboard/inbox`.
2. Dashboard layout renders `<KycBanner>` — for any business with `kyc_status='pending'`, shows a prompt linking to `/dashboard/settings/kyc`.
3. `/dashboard/settings/kyc` renders 4 `<KycDocumentCard>`s — one per doc type. Each card has an upload input + server-action submit button.
4. Server action validates (≤ 10 MB, PDF/JPEG/PNG only), uploads to the `kyc-documents` Storage bucket at path `businesses/{business_id}/{doc_type}/{safe_filename}`, and PATCHes `businesses.kyc_documents` jsonb with a reference.
5. Once all 4 docs are uploaded, the banner flips to "KYC under review."
6. Platform admin manually flips `businesses.kyc_status` to `verified` in Supabase Studio (no internal admin UI in Phase 1b).

## Storage RLS

The `kyc-documents` bucket's RLS policy scopes read/write to business members by parsing the UUID in the path. See `supabase/migrations/014_kyc_storage.sql`. Cross-business access is proved blocked by `supabase/tests/011_kyc_storage_rls.sql`.

## Drizzle vs Supabase CLI

Supabase CLI owns schema changes (migrations live in `../supabase/migrations/`). Drizzle is used only for TypeScript types and potentially for read queries in later phases. `drizzle-kit push` is never run.

To explore the schema with Drizzle Studio:
```bash
pnpm exec drizzle-kit studio
```

## Handoff to Phase 1b

- KYC document upload goes into `app/dashboard/settings/kyc/page.tsx` and Supabase Storage (`kyc-documents` bucket, private).
- The `businesses.kyc_status` enum already has `pending | verified | rejected`; 1a leaves every new business at `pending` — 1b adds UI to upload docs; platform_admin verifies externally (Supabase Studio) until a later phase builds an internal admin UI.
