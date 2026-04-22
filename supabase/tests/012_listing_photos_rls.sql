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
