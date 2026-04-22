BEGIN;
SELECT plan(4);

-- Seed similar to 005 but kennel is instant_book
INSERT INTO auth.users (id, email) VALUES ('a6661111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a6661111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a6661111-0000-0000-0000-000000000ee1','a6661111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a6661111-0000-0000-0000-000000000ee1','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b6661111-0000-0000-0000-000000000100','B','bi','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b6661111-0000-0000-0000-000000000200','b6661111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b6661111-0000-0000-0000-000000000300','b6661111-0000-0000-0000-000000000200',
        'K','dog','small',1,80,100,true);

SET LOCAL request.jwt.claim.sub = 'a6661111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT has_function('public','create_instant_booking',ARRAY['uuid','uuid[]','date','date','text']);

DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_instant_booking(
    'b6661111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a6661111-0000-0000-0000-000000000ee1'::uuid],
    '2026-08-01'::date, '2026-08-02'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'pending_payment'::booking_status, 'instant booking goes straight to pending_payment');

SELECT ok(
  (SELECT payment_deadline FROM bookings WHERE id = current_setting('petbnb.bid')::uuid)
  BETWEEN now() + interval '10 minutes' AND now() + interval '20 minutes',
  'payment_deadline is ~15 min away');

-- Capacity is 1; a second instant booking for overlapping days should fail
SELECT throws_like(
  'SELECT create_instant_booking(
     ''b6661111-0000-0000-0000-000000000300''::uuid,
     ARRAY[''a6661111-0000-0000-0000-000000000ee1''::uuid],
     ''2026-08-01''::date, ''2026-08-02''::date, NULL)',
  '%not available%',
  'overlapping instant booking fails');

SELECT * FROM finish();
ROLLBACK;
