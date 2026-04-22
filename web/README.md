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
