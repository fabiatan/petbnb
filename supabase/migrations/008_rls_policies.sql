-- Enable RLS on every table
ALTER TABLE user_profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE pets                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE vaccination_certs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE businesses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_members      ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE kennel_types          ENABLE ROW LEVEL SECURITY;
ALTER TABLE peak_calendar         ENABLE ROW LEVEL SECURITY;
ALTER TABLE availability_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_pets          ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_cert_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews               ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_responses      ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications         ENABLE ROW LEVEL SECURITY;

-- Helper: is the current auth.uid() a member of this business?
CREATE OR REPLACE FUNCTION is_business_member(p_business_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM business_members
    WHERE business_id = p_business_id AND user_id = auth.uid()
  );
$$;

-- user_profiles: users see + update own row
CREATE POLICY user_profiles_self_select ON user_profiles
  FOR SELECT USING (id = auth.uid());
CREATE POLICY user_profiles_self_update ON user_profiles
  FOR UPDATE USING (id = auth.uid());
CREATE POLICY user_profiles_self_insert ON user_profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- pets: owner-only
CREATE POLICY pets_owner ON pets
  FOR ALL USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

-- vaccination_certs: owner via join on pet
CREATE POLICY vax_owner ON vaccination_certs
  FOR ALL USING (
    EXISTS (SELECT 1 FROM pets WHERE pets.id = vaccination_certs.pet_id AND pets.owner_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM pets WHERE pets.id = vaccination_certs.pet_id AND pets.owner_id = auth.uid())
  );

-- businesses: public-read on verified+active rows (for discovery);
-- business_members have full access to their own rows.
CREATE POLICY businesses_public_read ON businesses
  FOR SELECT USING (kyc_status = 'verified' AND status = 'active');
-- NOTE: initial business creation + first business_members row must go through a
-- SECURITY DEFINER onboarding function — there is no direct INSERT path because
-- the WITH CHECK requires the caller to already be a member.
CREATE POLICY businesses_member_all ON businesses
  FOR ALL USING (is_business_member(id))
  WITH CHECK (is_business_member(id));

-- business_members: member sees own business's member list
CREATE POLICY business_members_member_read ON business_members
  FOR SELECT USING (is_business_member(business_id));

-- listings: public read; members full
CREATE POLICY listings_public_read ON listings
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM businesses b WHERE b.id = listings.business_id
            AND b.kyc_status = 'verified' AND b.status = 'active')
  );
CREATE POLICY listings_member_all ON listings
  FOR ALL USING (is_business_member(business_id))
  WITH CHECK (is_business_member(business_id));

-- kennel_types: public read (via listing); members full
CREATE POLICY kennel_types_public_read ON kennel_types
  FOR SELECT USING (
    active AND EXISTS (
      SELECT 1 FROM listings l JOIN businesses b ON b.id = l.business_id
      WHERE l.id = kennel_types.listing_id
        AND b.kyc_status = 'verified' AND b.status = 'active'
    )
  );
CREATE POLICY kennel_types_member_all ON kennel_types
  FOR ALL USING (
    EXISTS (SELECT 1 FROM listings l WHERE l.id = kennel_types.listing_id AND is_business_member(l.business_id))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM listings l WHERE l.id = kennel_types.listing_id AND is_business_member(l.business_id))
  );

-- peak_calendar: public rows readable to all; per-business rows scoped
CREATE POLICY peak_calendar_public_read ON peak_calendar
  FOR SELECT USING (business_id IS NULL OR is_business_member(business_id));
CREATE POLICY peak_calendar_member_write ON peak_calendar
  FOR ALL USING (business_id IS NOT NULL AND is_business_member(business_id))
  WITH CHECK (business_id IS NOT NULL AND is_business_member(business_id));

-- availability_overrides: members-only
CREATE POLICY availability_overrides_member_all ON availability_overrides
  FOR ALL USING (
    EXISTS (SELECT 1 FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
            WHERE kt.id = availability_overrides.kennel_type_id
              AND is_business_member(l.business_id))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
            WHERE kt.id = availability_overrides.kennel_type_id
              AND is_business_member(l.business_id))
  );

-- bookings: owner sees own; business_admin sees own business's bookings
CREATE POLICY bookings_owner_read ON bookings
  FOR SELECT USING (owner_id = auth.uid());
CREATE POLICY bookings_business_read ON bookings
  FOR SELECT USING (is_business_member(business_id));
-- No INSERT/UPDATE policies: all mutations go through SECURITY DEFINER functions.

-- booking_pets: via booking join
CREATE POLICY booking_pets_read ON booking_pets
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM bookings b WHERE b.id = booking_pets.booking_id
            AND (b.owner_id = auth.uid() OR is_business_member(b.business_id)))
  );

-- booking_cert_snapshots: same visibility as parent booking
CREATE POLICY cert_snapshots_read ON booking_cert_snapshots
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM bookings b WHERE b.id = booking_cert_snapshots.booking_id
            AND (b.owner_id = auth.uid() OR is_business_member(b.business_id)))
  );

-- reviews: public read (verified businesses only); owner writes
-- Reviews are intentionally immutable after posting. No UPDATE or DELETE policies.
-- If an owner needs to amend a review, the platform handles it via SECURITY DEFINER.
CREATE POLICY reviews_public_read ON reviews
  FOR SELECT USING (true);
CREATE POLICY reviews_owner_insert ON reviews
  FOR INSERT WITH CHECK (owner_id = auth.uid());

-- review_responses: public read; business members write
CREATE POLICY review_responses_public_read ON review_responses
  FOR SELECT USING (true);
CREATE POLICY review_responses_member_write ON review_responses
  FOR ALL USING (is_business_member(business_id))
  WITH CHECK (is_business_member(business_id));

-- notifications: recipient only
CREATE POLICY notifications_recipient ON notifications
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
