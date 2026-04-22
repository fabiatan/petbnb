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

-- Seed the non-member user while still in superuser context
-- (plan had these after RESET role but before re-impersonation — moved here
-- to avoid permission denied on auth.users when role = authenticated)
INSERT INTO auth.users (id, email) VALUES ('99999999-0000-0000-0000-000000000001', 'noone@t');
INSERT INTO user_profiles (id, display_name) VALUES ('99999999-0000-0000-0000-000000000001', 'No One');

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
  NULL,      -- skip errmsg match; only assert SQLSTATE
  'non-member cannot upload into Biz A folder');

SELECT * FROM finish();
ROLLBACK;
