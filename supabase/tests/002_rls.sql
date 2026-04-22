BEGIN;
SELECT plan(4);

-- Create two auth users
INSERT INTO auth.users (id, email)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@biz-a.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@biz-b.test');

INSERT INTO user_profiles (id, display_name, primary_role)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Alice', 'business_admin'),
  ('22222222-2222-2222-2222-222222222222', 'Bob', 'business_admin');

-- Two businesses
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Biz A', 'biz-a', '1 A St', 'KL', 'WP', 'verified', 'active'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Biz B', 'biz-b', '1 B St', 'KL', 'WP', 'verified', 'active');

INSERT INTO business_members (business_id, user_id) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222');

INSERT INTO listings (id, business_id) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES
  ('aaaa0000-0000-0000-0000-000000000001', '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'A-Small', 'dog', 'small', 4, 80, 100),
  ('bbbb0000-0000-0000-0000-000000000001', '22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'B-Small', 'dog', 'small', 4, 80, 100);

-- Create an owner + pet
INSERT INTO auth.users (id, email) VALUES ('33333333-3333-3333-3333-333333333333', 'owner@test');
INSERT INTO user_profiles (id, display_name) VALUES ('33333333-3333-3333-3333-333333333333', 'Owner');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('99999999-9999-9999-9999-999999999999', '33333333-3333-3333-3333-333333333333', 'Mochi', 'dog');

-- Booking at Biz A only
INSERT INTO bookings (
  id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status
) VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '33333333-3333-3333-3333-333333333333',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'aaaa0000-0000-0000-0000-000000000001',
  '2026-05-01', '2026-05-03', 2, 160, 'confirmed'
);

-- Switch to Alice (Biz A admin)
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM bookings), 1, 'Alice sees Biz A booking');

-- Switch to Bob (Biz B admin)
RESET role;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM bookings), 0, 'Bob sees 0 bookings (Biz B has none)');

-- Bob cannot read Biz A by id either
SELECT is((SELECT count(*)::int FROM bookings WHERE business_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0,
  'Bob cannot see Biz A booking by direct filter');

-- Owner can see their own booking
RESET role;
SET LOCAL request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
SET LOCAL role = 'authenticated';
SELECT is((SELECT count(*)::int FROM bookings), 1, 'Owner sees own booking');

SELECT * FROM finish();
ROLLBACK;
