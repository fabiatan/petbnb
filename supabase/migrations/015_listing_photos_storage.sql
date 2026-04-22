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
