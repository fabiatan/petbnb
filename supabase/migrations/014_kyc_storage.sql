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

-- Note: ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY is omitted here
-- because storage.objects is owned by supabase_storage_admin (not postgres),
-- so the migration role cannot execute it. RLS is already enabled by default
-- on this Supabase version (confirmed: relrowsecurity=t). No action needed.
