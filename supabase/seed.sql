-- Dev-only seed data. Safe to re-run.

-- Auth users
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'owner1@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('10000000-0000-0000-0000-000000000002', 'owner2@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000001', 'admin-a@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated'),
  ('20000000-0000-0000-0000-000000000002', 'admin-b@petbnb.local', '{}'::jsonb, 'authenticated', 'authenticated')
ON CONFLICT DO NOTHING;

INSERT INTO user_profiles (id, display_name, primary_role) VALUES
  ('10000000-0000-0000-0000-000000000001', 'Dev Owner 1', 'owner'),
  ('10000000-0000-0000-0000-000000000002', 'Dev Owner 2', 'owner'),
  ('20000000-0000-0000-0000-000000000001', 'Admin - Happy Paws KL', 'business_admin'),
  ('20000000-0000-0000-0000-000000000002', 'Admin - Bark Avenue',   'business_admin')
ON CONFLICT DO NOTHING;

-- Pets + certs
INSERT INTO pets (id, owner_id, name, species, breed, weight_kg) VALUES
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Mochi','dog','Poodle',8),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Luna','cat','DSH',4.2)
ON CONFLICT DO NOTHING;

INSERT INTO vaccination_certs (pet_id, file_url, vaccines_covered, issued_on, expires_on) VALUES
  ('30000000-0000-0000-0000-000000000001','https://example.test/cert-mochi.pdf','{rabies,core}','2025-01-15','2028-01-15'),
  ('30000000-0000-0000-0000-000000000002','https://example.test/cert-luna.pdf','{fvrcp}','2025-03-01','2028-03-01')
ON CONFLICT DO NOTHING;

-- Businesses
INSERT INTO businesses (id, name, slug, address, city, state, kyc_status, status, commission_rate_bps) VALUES
  ('40000000-0000-0000-0000-000000000001','Happy Paws KL','happy-paws-kl','1 Mont Kiara','Kuala Lumpur','WP','verified','active',1200),
  ('40000000-0000-0000-0000-000000000002','Bark Avenue',  'bark-avenue',  '2 Bangsar',   'Kuala Lumpur','WP','verified','active',1200)
ON CONFLICT DO NOTHING;

INSERT INTO business_members (business_id, user_id) VALUES
  ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002')
ON CONFLICT DO NOTHING;

INSERT INTO listings (id, business_id, amenities, house_rules, cancellation_policy) VALUES
  ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',
    ARRAY['air_con','daily_walks','cctv'],'No aggressive dogs','moderate'),
  ('50000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002',
    ARRAY['outdoor_run','grooming'],'Vaccinations required','flexible')
ON CONFLICT DO NOTHING;

INSERT INTO kennel_types (id, listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book) VALUES
  ('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','Small Dog Suite','dog','small',4,80,100,true),
  ('60000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001','Large Dog Suite','dog','large',2,120,150,false),
  ('60000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001','Cat Room','cat','small',6,60,75,false),
  ('60000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-000000000002','Large Dog Suite','dog','large',3,95,115,false)
ON CONFLICT DO NOTHING;
