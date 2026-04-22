-- Harness: helpers reused across test files.
-- Supabase test runner wraps each test file in a transaction that's rolled back,
-- so seed data created here is isolated to the file using it.

BEGIN;
SELECT plan(1);
SELECT ok(true, 'harness loads');
SELECT * FROM finish();
ROLLBACK;
