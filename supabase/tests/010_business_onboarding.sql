BEGIN;
SELECT plan(7);

-- Create an auth user + profile
INSERT INTO auth.users (id, email) VALUES
  ('aaaa1100-0000-0000-0000-000000000001', 'newadmin@petbnb.test');
INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('aaaa1100-0000-0000-0000-000000000001', 'New Admin', 'business_admin');

-- Function exists
SELECT has_function('public', 'create_business_onboarding',
  ARRAY['text','text','text','text','text']);

-- Impersonate the user
SET LOCAL request.jwt.claim.sub = 'aaaa1100-0000-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

-- Call the function
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := create_business_onboarding(
    'Happy Paws Test',
    'happy-paws-test',
    '1 Mont Kiara',
    'Kuala Lumpur',
    'WP'
  );
  PERFORM set_config('petbnb.biz_id', v_id::text, true);
END $$;

-- Business was created with caller as member
SELECT isnt((SELECT current_setting('petbnb.biz_id')), NULL, 'returns a business id');

SELECT is(
  (SELECT name FROM businesses WHERE id = current_setting('petbnb.biz_id')::uuid),
  'Happy Paws Test', 'business name stored correctly');

SELECT is(
  (SELECT count(*)::int FROM business_members
    WHERE business_id = current_setting('petbnb.biz_id')::uuid
      AND user_id = 'aaaa1100-0000-0000-0000-000000000001'),
  1, 'caller is a member of the new business');

SELECT is(
  (SELECT count(*)::int FROM listings
    WHERE business_id = current_setting('petbnb.biz_id')::uuid),
  1, 'stub listing row created');

-- kyc_status defaults to 'pending'
SELECT is(
  (SELECT kyc_status::text FROM businesses WHERE id = current_setting('petbnb.biz_id')::uuid),
  'pending', 'kyc_status defaults to pending');

-- Duplicate slug errors
SELECT throws_like(
  $$ SELECT create_business_onboarding(
      'Happy Paws Test 2', 'happy-paws-test', '2 KL', 'KL', 'WP') $$,
  '%duplicate key%',
  'duplicate slug rejected');

SELECT * FROM finish();
ROLLBACK;
