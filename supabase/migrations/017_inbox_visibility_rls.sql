-- Business admins need to see pet + owner info for rendering the Inbox UI.
-- Scope: only rows linked to a booking at their own business.

-- pets: business_admin SELECT if any booking_pets row connects this pet to a
-- booking at caller's business.
CREATE POLICY pets_business_read ON pets
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM booking_pets bp
      JOIN bookings b ON b.id = bp.booking_id
      WHERE bp.pet_id = pets.id
        AND is_business_member(b.business_id)
    )
  );

-- user_profiles: business_admin SELECT if this user has any booking at caller's
-- business.
CREATE POLICY user_profiles_business_read ON user_profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.owner_id = user_profiles.id
        AND is_business_member(b.business_id)
    )
  );
