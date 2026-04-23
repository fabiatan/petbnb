-- Pet vaccination certificates. Private bucket; only the pet's owner
-- can read or write. Path convention: pets/{pet_id}/{unique-filename}

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pet-vaccinations',
  'pet-vaccinations',
  false,
  10485760,                                   -- 10 MiB
  ARRAY['application/pdf','image/jpeg','image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Helper: is the current auth.uid() the owner of this pet?
-- SECURITY DEFINER + locked search_path for the same reason is_business_member
-- needs it: calling RLS policies across tables otherwise re-triggers RLS on
-- the joined table and silently filters out all rows.
CREATE OR REPLACE FUNCTION is_pet_owner(p_pet_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM pets
    WHERE id = p_pet_id AND owner_id = auth.uid()
  );
$$;

-- RLS: pet's owner can CRUD. Check via helper; path second segment = pet UUID.
DROP POLICY IF EXISTS "pet_vax_owner_all" ON storage.objects;
CREATE POLICY "pet_vax_owner_all"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'pet-vaccinations'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'pets'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND is_pet_owner((storage.foldername(name))[2]::uuid)
)
WITH CHECK (
  bucket_id = 'pet-vaccinations'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'pets'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND is_pet_owner((storage.foldername(name))[2]::uuid)
);
