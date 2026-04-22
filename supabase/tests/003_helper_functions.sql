BEGIN;
SELECT plan(5);

-- Seed: a kennel with base RM80, peak RM100
INSERT INTO auth.users (id, email) VALUES ('aaaaaaaa-1111-1111-1111-111111111111','setup@t');
INSERT INTO user_profiles (id, display_name) VALUES ('aaaaaaaa-1111-1111-1111-111111111111','Setup');
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status)
VALUES ('11111111-2222-3333-4444-555555555555','Setup Biz','setup-biz','','KL','WP','verified','active');
INSERT INTO business_members (business_id, user_id) VALUES
  ('11111111-2222-3333-4444-555555555555','aaaaaaaa-1111-1111-1111-111111111111');
INSERT INTO listings (id, business_id) VALUES
  ('11111111-2222-3333-4444-666666666666','11111111-2222-3333-4444-555555555555');
INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
VALUES ('11111111-2222-3333-4444-777777777777','11111111-2222-3333-4444-666666666666',
        'Small','dog','small',4,80,100);

-- Seed peak calendar: 2026-04-15 is peak (global)
INSERT INTO peak_calendar (date, label) VALUES ('2026-04-15', 'Test weekend');

-- compute_stay_subtotal returns numeric
SELECT has_function('public', 'compute_stay_subtotal', ARRAY['uuid','date','date']);

-- 2 nights, one off-peak, one peak => 80 + 100 = 180
SELECT is(compute_stay_subtotal(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-04-14'::date, '2026-04-16'::date),
  180::numeric, '2 nights, 1 off-peak + 1 peak = 180');

-- 1 night, off-peak => 80
SELECT is(compute_stay_subtotal(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-04-14'::date, '2026-04-15'::date),
  80::numeric, '1 night off-peak = 80');

-- kennel_available checks capacity - (confirmed+pending) >= 1
SELECT has_function('public', 'kennel_available', ARRAY['uuid','date','date','integer']);

-- Empty kennel: capacity 4, needed 1 => available
SELECT ok(kennel_available(
  '11111111-2222-3333-4444-777777777777'::uuid,
  '2026-04-14'::date, '2026-04-16'::date, 1),
  'empty kennel is available');

SELECT * FROM finish();
ROLLBACK;
