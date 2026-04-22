BEGIN;
SELECT plan(5);

-- Seed a business + kennel + owner with insertable requested + confirmed rows
INSERT INTO auth.users (id, email) VALUES ('a9991111-0000-0000-0000-000000000001','o@t');
INSERT INTO user_profiles (id, display_name) VALUES ('a9991111-0000-0000-0000-000000000001','O');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('a9991111-0000-0000-0000-000000000ee1','a9991111-0000-0000-0000-000000000001','X','dog');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('b9991111-0000-0000-0000-000000000100','B','bl','','KL','WP','verified','active');
INSERT INTO listings (id, business_id) VALUES
  ('b9991111-0000-0000-0000-000000000200','b9991111-0000-0000-0000-000000000100');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book)
VALUES ('b9991111-0000-0000-0000-000000000300','b9991111-0000-0000-0000-000000000200','K','dog','small',3,80,100,false);

-- Insert a stale 'requested' (older than 24h) directly
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000001',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-01-01','2027-01-02',1,80,'requested', now()-interval '25 hours', NULL);

-- Insert a fresh 'requested' (within window) -> should NOT expire
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000002',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-02-01','2027-02-02',1,80,'requested', now()-interval '1 hour', NULL);

-- Insert a stale pending_payment (past deadline)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at, payment_deadline)
VALUES ('c1111111-0000-0000-0000-000000000003',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  '2027-03-01','2027-03-02',1,80,'pending_payment', now()-interval '1 hour', now()-interval '10 minutes');

-- Insert a past confirmed booking (check_out yesterday)
INSERT INTO bookings (id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status, requested_at)
VALUES ('c1111111-0000-0000-0000-000000000004',
  'a9991111-0000-0000-0000-000000000001',
  'b9991111-0000-0000-0000-000000000100',
  'b9991111-0000-0000-0000-000000000200',
  'b9991111-0000-0000-0000-000000000300',
  CURRENT_DATE - interval '5 days', CURRENT_DATE - interval '1 day', 4, 320, 'confirmed', now()-interval '10 days');

SELECT has_function('public','sweep_expire_stale_requests',ARRAY[]::text[]);

SELECT lives_ok('SELECT sweep_expire_stale_requests()', 'stale-request sweep runs');
SELECT is(
  (SELECT status FROM bookings WHERE id = 'c1111111-0000-0000-0000-000000000001'),
  'expired'::booking_status, 'stale requested booking expired');
SELECT is(
  (SELECT status FROM bookings WHERE id = 'c1111111-0000-0000-0000-000000000002'),
  'requested'::booking_status, 'fresh requested booking kept');

SELECT lives_ok('SELECT sweep_expire_stale_payments()', 'payment-expire sweep runs');

SELECT * FROM finish();
ROLLBACK;
