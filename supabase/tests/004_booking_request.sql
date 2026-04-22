BEGIN;
SELECT plan(6);

-- Seed: owner, pet, cert, business, listing, kennel
INSERT INTO auth.users (id, email) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','owner@t'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admin@t');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Owner','owner'),
  ('22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Admin','business_admin');

INSERT INTO pets (id, owner_id, name, species) VALUES
  ('33333333-cccc-cccc-cccc-cccccccccccc','11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Mochi','dog');

-- Cert valid until 2027
INSERT INTO vaccination_certs (pet_id, file_url, vaccines_covered, issued_on, expires_on)
VALUES ('33333333-cccc-cccc-cccc-cccccccccccc','https://x','{rabies}','2025-01-01','2027-01-01');

INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status) VALUES
  ('44444444-dddd-dddd-dddd-dddddddddddd','Biz','biz','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('44444444-dddd-dddd-dddd-dddddddddddd','22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
INSERT INTO listings (id, business_id) VALUES
  ('55555555-eeee-eeee-eeee-eeeeeeeeeeee','44444444-dddd-dddd-dddd-dddddddddddd');

-- Non-instant-book kennel
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('66666666-ffff-ffff-ffff-ffffffffffff','55555555-eeee-eeee-eeee-eeeeeeeeeeee',
        'Small','dog','small',2,80,100,false);

-- Impersonate owner
SET LOCAL request.jwt.claim.sub = '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET LOCAL role = 'authenticated';

-- Happy path
SELECT has_function('public', 'create_booking_request', ARRAY['uuid','uuid[]','date','date','text']);

DO $$
DECLARE v_booking_id uuid;
BEGIN
  v_booking_id := create_booking_request(
    '66666666-ffff-ffff-ffff-ffffffffffff'::uuid,
    ARRAY['33333333-cccc-cccc-cccc-cccccccccccc'::uuid],
    '2026-04-14'::date, '2026-04-16'::date,
    'Test notes'
  );
  PERFORM set_config('petbnb.test_booking_id', v_booking_id::text, true);
END $$;

SELECT is(
  (SELECT status FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  'requested'::booking_status,
  'new booking is requested');

SELECT is(
  (SELECT nights FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  2, 'nights = 2');

SELECT is(
  (SELECT subtotal_myr FROM bookings WHERE id = current_setting('petbnb.test_booking_id')::uuid),
  160::numeric, 'subtotal = 2 * 80 = 160');

-- Cert snapshot created
SELECT is(
  (SELECT count(*)::int FROM booking_cert_snapshots
     WHERE booking_id = current_setting('petbnb.test_booking_id')::uuid),
  1, 'one cert snapshotted');

-- Illegal: instant-book kennel cannot go through request path.
-- RESET role to postgres so the UPDATE bypasses RLS (owner isn't a business member).
RESET role;
UPDATE kennel_types SET instant_book = true WHERE id = '66666666-ffff-ffff-ffff-ffffffffffff';
SET LOCAL request.jwt.claim.sub = '11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SET LOCAL role = 'authenticated';
SELECT throws_like(
  $ct$ SELECT create_booking_request(
    '66666666-ffff-ffff-ffff-ffffffffffff'::uuid,
    ARRAY['33333333-cccc-cccc-cccc-cccccccccccc'::uuid],
    '2026-06-01'::date, '2026-06-02'::date, NULL)
  $ct$,
  '%instant_book%',
  'cannot request-to-book an instant-book kennel'
);

SELECT * FROM finish();
ROLLBACK;
