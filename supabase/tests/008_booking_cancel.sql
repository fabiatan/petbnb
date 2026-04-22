BEGIN;
SELECT plan(5);

INSERT INTO auth.users (id, email) VALUES
  ('a8881111-0000-0000-0000-000000000001','o@t'),
  ('b8881111-0000-0000-0000-000000000002','adm@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('a8881111-0000-0000-0000-000000000001','O'),
  ('b8881111-0000-0000-0000-000000000002','Adm');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a8881111-0000-0000-0000-000000000ee1','a8881111-0000-0000-0000-000000000001','X','dog');
INSERT INTO vaccination_certs (pet_id, file_url, issued_on, expires_on)
VALUES ('a8881111-0000-0000-0000-000000000ee1','x','2025-01-01','2027-01-01');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b8881111-0000-0000-0000-000000000100','B','bk','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('b8881111-0000-0000-0000-000000000100','b8881111-0000-0000-0000-000000000002');
INSERT INTO listings (id, business_id) VALUES
  ('b8881111-0000-0000-0000-000000000200','b8881111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b8881111-0000-0000-0000-000000000300','b8881111-0000-0000-0000-000000000200','K','dog','small',2,80,100,true);

-- Owner creates + pays (via helpers) -> confirmed
SET LOCAL request.jwt.claim.sub = 'a8881111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';
DO $$
DECLARE v_id uuid; v_ref text;
BEGIN
  v_id := create_instant_booking(
    'b8881111-0000-0000-0000-000000000300'::uuid,
    ARRAY['a8881111-0000-0000-0000-000000000ee1'::uuid],
    '2026-10-01'::date, '2026-10-03'::date, NULL);
  v_ref := create_payment_intent(v_id);
  PERFORM set_config('petbnb.bid', v_id::text, true);
  PERFORM set_config('petbnb.ref', v_ref, true);
END $$;
RESET role;
SELECT confirm_payment(current_setting('petbnb.ref'), 160::numeric);

-- Owner cancels
SET LOCAL request.jwt.claim.sub = 'a8881111-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT has_function('public','cancel_booking_by_owner',ARRAY['uuid']);
SELECT lives_ok(
  'SELECT cancel_booking_by_owner((SELECT current_setting(''petbnb.bid'')::uuid))',
  'owner cancels confirmed booking');
SELECT is(
  (SELECT status FROM bookings WHERE id = current_setting('petbnb.bid')::uuid),
  'cancelled_by_owner'::booking_status, 'status=cancelled_by_owner');

-- Cancelling again errors
SELECT throws_like(
  'SELECT cancel_booking_by_owner((SELECT current_setting(''petbnb.bid'')::uuid))',
  '%not confirmed%',
  'cannot cancel twice');

SELECT has_function('public','cancel_booking_by_business',ARRAY['uuid','text']);

SELECT * FROM finish();
ROLLBACK;
