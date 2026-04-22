BEGIN;
SELECT plan(6);

-- Reusable seed: owner, pet+cert, business admin, kennel, requested booking
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1111-0000-0000-0000-000000000001','owner@t'),
  ('bbbb1111-0000-0000-0000-000000000002','admin@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('aaaa1111-0000-0000-0000-000000000001','Owner'),
  ('bbbb1111-0000-0000-0000-000000000002','Admin');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('aaaa1111-0000-0000-0000-000000000ee1','aaaa1111-0000-0000-0000-000000000001','M','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on) VALUES
  ('aaaa1111-0000-0000-0000-000000000ee1','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('bbbb1111-0000-0000-0000-000000000100','B','b','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('bbbb1111-0000-0000-0000-000000000100','bbbb1111-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('bbbb1111-0000-0000-0000-000000000200','bbbb1111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES ('bbbb1111-0000-0000-0000-000000000300','bbbb1111-0000-0000-0000-000000000200',
        'K','dog','small',2,80,100);

-- Owner creates request
SET LOCAL request.jwt.claim.sub = 'aaaa1111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_booking_request(
    'bbbb1111-0000-0000-0000-000000000300'::uuid,
    ARRAY['aaaa1111-0000-0000-0000-000000000ee1'::uuid],
    '2026-06-01'::date, '2026-06-03'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

-- Admin accepts
RESET role;
SET LOCAL request.jwt.claim.sub = 'bbbb1111-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT has_function('public','accept_booking',ARRAY['uuid']);
SELECT lives_ok(
  'SELECT accept_booking((SELECT current_setting(''petbnb.bid'')::uuid))',
  'admin can accept');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'accepted'::booking_status, 'status flipped to accepted');

-- Idempotency check: re-accepting errors
SELECT throws_like(
  'SELECT accept_booking((SELECT current_setting(''petbnb.bid'')::uuid))',
  '%not in requested%',
  'cannot accept twice');

-- Now test decline on a fresh booking
RESET role;
SET LOCAL request.jwt.claim.sub = 'aaaa1111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_booking_request(
    'bbbb1111-0000-0000-0000-000000000300'::uuid,
    ARRAY['aaaa1111-0000-0000-0000-000000000ee1'::uuid],
    '2026-07-01'::date, '2026-07-02'::date, NULL);
  PERFORM set_config('petbnb.bid2', v_id::text, true);
END $$;

RESET role;
SET LOCAL request.jwt.claim.sub = 'bbbb1111-0000-0000-0000-000000000002';
SET LOCAL role = 'authenticated';

SELECT lives_ok(
  'SELECT decline_booking((SELECT current_setting(''petbnb.bid2'')::uuid))',
  'admin can decline');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid2')::uuid),
  'declined'::booking_status, 'declined recorded');

SELECT * FROM finish();
ROLLBACK;
