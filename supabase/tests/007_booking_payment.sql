BEGIN;
SELECT plan(7);

-- Seed from 005 re-used (minimal here for brevity)
INSERT INTO auth.users (id, email) VALUES ('a7771111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a7771111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a7771111-0000-0000-0000-000000000ee1','a7771111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a7771111-0000-0000-0000-000000000ee1','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b7771111-0000-0000-0000-000000000100','B','bj','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b7771111-0000-0000-0000-000000000200','b7771111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b7771111-0000-0000-0000-000000000300','b7771111-0000-0000-0000-000000000200',
        'K','dog','small',1,80,100,true);

SET LOCAL request.jwt.claim.sub = 'a7771111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Create a pending_payment via instant-book
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_instant_booking(
    'b7771111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a7771111-0000-0000-0000-000000000ee1'::uuid],
    '2026-09-01'::date, '2026-09-03'::date, NULL);
  PERFORM set_config('petbnb.bid', v_id::text, true);
END $$;

SELECT has_function('public','create_payment_intent',ARRAY['uuid']);

DO $$
DECLARE v_ref text;
BEGIN
  v_ref := create_payment_intent(current_setting('petbnb.bid')::uuid);
  PERFORM set_config('petbnb.ref', v_ref, true);
END $$;

SELECT isnt((SELECT current_setting('petbnb.ref')), NULL, 'ref_no returned');

SELECT is((SELECT ipay88_reference FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  current_setting('petbnb.ref'), 'ref stored on booking');

-- confirm_payment flips to confirmed and is idempotent
-- Run as service_role (bypasses RLS check but SECURITY DEFINER function still checks state)
RESET role;

SELECT has_function('public','confirm_payment',ARRAY['text','numeric']);

SELECT lives_ok(
  format('SELECT confirm_payment(%L, 160::numeric)', current_setting('petbnb.ref')),
  'first confirm_payment succeeds');

SELECT is((SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'confirmed'::booking_status, 'booking is confirmed');

-- Idempotency: second call is a no-op, does not error
SELECT lives_ok(
  format('SELECT confirm_payment(%L, 160::numeric)', current_setting('petbnb.ref')),
  'second confirm_payment is idempotent (no error)');

SELECT * FROM finish();
ROLLBACK;
