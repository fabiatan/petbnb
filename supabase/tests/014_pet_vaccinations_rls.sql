BEGIN;
SELECT plan(5);

-- All auth.users + user_profiles inserts at the top, before any SET LOCAL role.
INSERT INTO auth.users (id, email) VALUES
  ('11111111-2a00-0000-0000-000000000001', 'alice2a@t'),
  ('11111111-2a00-0000-0000-000000000002', 'bob2a@t'),
  ('11111111-2a00-0000-0000-000000000099', 'carol@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('11111111-2a00-0000-0000-000000000001', 'Alice'),
  ('11111111-2a00-0000-0000-000000000002', 'Bob'),
  ('11111111-2a00-0000-0000-000000000099', 'Carol');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('aaaa2a00-0000-0000-0000-000000000001', '11111111-2a00-0000-0000-000000000001', 'Mochi', 'dog'),
  ('aaaa2a00-0000-0000-0000-000000000002', '11111111-2a00-0000-0000-000000000002', 'Luna', 'cat');

-- Seed one file per pet as postgres (bypass RLS)
INSERT INTO storage.objects (bucket_id, name, owner, metadata) VALUES
  ('pet-vaccinations',
   'pets/aaaa2a00-0000-0000-0000-000000000001/cert.pdf',
   '11111111-2a00-0000-0000-000000000001',
   '{"mimetype":"application/pdf"}'::jsonb),
  ('pet-vaccinations',
   'pets/aaaa2a00-0000-0000-0000-000000000002/cert.pdf',
   '11111111-2a00-0000-0000-000000000002',
   '{"mimetype":"application/pdf"}'::jsonb);

-- Alice
SET LOCAL request.jwt.claim.sub = '11111111-2a00-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  1, 'Alice sees only her pet cert');
SELECT lives_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('pet-vaccinations',
             'pets/aaaa2a00-0000-0000-0000-000000000001/cert2.pdf',
             '11111111-2a00-0000-0000-000000000001',
             '{"mimetype":"application/pdf"}'::jsonb) $$,
  'Alice can insert under her own pet');

SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('pet-vaccinations',
             'pets/aaaa2a00-0000-0000-0000-000000000002/hack.pdf',
             '11111111-2a00-0000-0000-000000000001',
             '{"mimetype":"application/pdf"}'::jsonb) $$,
  '42501', NULL,
  'Alice cannot insert under Bob''s pet');

-- Anonymous
RESET role;
SET LOCAL role = 'anon';
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  0, 'anon sees nothing in private bucket');

-- Carol (authenticated, no pets)
RESET role;
SET LOCAL request.jwt.claim.sub = '11111111-2a00-0000-0000-000000000099';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  0, 'user with no pets sees no pet-vaccination files');

SELECT * FROM finish();
ROLLBACK;
