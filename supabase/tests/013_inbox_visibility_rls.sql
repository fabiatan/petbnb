BEGIN;
SELECT plan(6);

-- Two businesses, two owners. Owner A books at biz A; owner B books at biz B.
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1d00-0000-0000-0000-000000000001', 'admin-a@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000002', 'admin-b@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000011', 'owner-a@1d.t'),
  ('aaaa1d00-0000-0000-0000-000000000012', 'owner-b@1d.t');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('aaaa1d00-0000-0000-0000-000000000001', 'Admin A', 'business_admin'),
  ('aaaa1d00-0000-0000-0000-000000000002', 'Admin B', 'business_admin'),
  ('aaaa1d00-0000-0000-0000-000000000011', 'Owner A', 'owner'),
  ('aaaa1d00-0000-0000-0000-000000000012', 'Owner B', 'owner');

INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('bbbb1d00-0000-0000-0000-000000000001', 'Biz A-1d', 'biz-a-1d', '1 A', 'KL', 'WP', 'verified', 'active'),
  ('bbbb1d00-0000-0000-0000-000000000002', 'Biz B-1d', 'biz-b-1d', '1 B', 'KL', 'WP', 'verified', 'active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('bbbb1d00-0000-0000-0000-000000000001', 'aaaa1d00-0000-0000-0000-000000000001'),
  ('bbbb1d00-0000-0000-0000-000000000002', 'aaaa1d00-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('cccc1d00-0000-0000-0000-000000000001', 'bbbb1d00-0000-0000-0000-000000000001'),
  ('cccc1d00-0000-0000-0000-000000000002', 'bbbb1d00-0000-0000-0000-000000000002');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES
  ('dddd1d00-0000-0000-0000-000000000001', 'cccc1d00-0000-0000-0000-000000000001', 'A-K', 'dog', 'small', 4, 80, 100),
  ('dddd1d00-0000-0000-0000-000000000002', 'cccc1d00-0000-0000-0000-000000000002', 'B-K', 'dog', 'small', 4, 80, 100);

-- Pets
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('eeee1d00-0000-0000-0000-000000000a01', 'aaaa1d00-0000-0000-0000-000000000011', 'PetA', 'dog'),
  ('eeee1d00-0000-0000-0000-000000000b01', 'aaaa1d00-0000-0000-0000-000000000012', 'PetB', 'dog');

-- Bookings (owner A → biz A; owner B → biz B)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status)
VALUES
  ('ffff1d00-0000-0000-0000-000000000001',
   'aaaa1d00-0000-0000-0000-000000000011',
   'bbbb1d00-0000-0000-0000-000000000001',
   'cccc1d00-0000-0000-0000-000000000001',
   'dddd1d00-0000-0000-0000-000000000001',
   '2027-01-01', '2027-01-03', 2, 160, 'requested'),
  ('ffff1d00-0000-0000-0000-000000000002',
   'aaaa1d00-0000-0000-0000-000000000012',
   'bbbb1d00-0000-0000-0000-000000000002',
   'cccc1d00-0000-0000-0000-000000000002',
   'dddd1d00-0000-0000-0000-000000000002',
   '2027-01-01', '2027-01-03', 2, 160, 'requested');
INSERT INTO booking_pets (booking_id, pet_id) VALUES
  ('ffff1d00-0000-0000-0000-000000000001', 'eeee1d00-0000-0000-0000-000000000a01'),
  ('ffff1d00-0000-0000-0000-000000000002', 'eeee1d00-0000-0000-0000-000000000b01');

-- Impersonate Admin A
SET LOCAL request.jwt.claim.sub = 'aaaa1d00-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Sees PetA
SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000a01'),
  1, 'Admin A can read own customer pet');

-- Does NOT see PetB
SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000b01'),
  0, 'Admin A cannot read Biz B customer pet');

-- Sees Owner A profile
SELECT is(
  (SELECT count(*)::int FROM user_profiles WHERE id = 'aaaa1d00-0000-0000-0000-000000000011'),
  1, 'Admin A can read own customer profile');

-- Does NOT see Owner B profile
SELECT is(
  (SELECT count(*)::int FROM user_profiles WHERE id = 'aaaa1d00-0000-0000-0000-000000000012'),
  0, 'Admin A cannot read Biz B customer profile');

-- Impersonate Admin B
RESET role;
SET LOCAL request.jwt.claim.sub = 'aaaa1d00-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000b01'),
  1, 'Admin B can read own customer pet');

SELECT is(
  (SELECT count(*)::int FROM pets WHERE id = 'eeee1d00-0000-0000-0000-000000000a01'),
  0, 'Admin B cannot read Biz A customer pet');

SELECT * FROM finish();
ROLLBACK;
