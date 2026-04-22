BEGIN;
SELECT plan(8);

SELECT has_table('public'::name, 'user_profiles'::name);
SELECT has_table('public'::name, 'pets'::name);
SELECT has_table('public'::name, 'businesses'::name);
SELECT has_table('public'::name, 'listings'::name);
SELECT has_table('public'::name, 'kennel_types'::name);
SELECT has_table('public'::name, 'bookings'::name);
SELECT has_table('public'::name, 'reviews'::name);
SELECT has_enum('public'::name, 'booking_status'::name);

SELECT * FROM finish();
ROLLBACK;
