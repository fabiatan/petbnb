CREATE INDEX pets_owner_id_idx ON pets(owner_id);
CREATE INDEX vaccination_certs_pet_id_idx ON vaccination_certs(pet_id);
CREATE INDEX vaccination_certs_expires_on_idx ON vaccination_certs(expires_on);

CREATE INDEX business_members_user_id_idx ON business_members(user_id);
CREATE INDEX business_members_business_id_idx ON business_members(business_id);

CREATE INDEX listings_business_id_idx ON listings(business_id);
CREATE INDEX kennel_types_listing_id_idx ON kennel_types(listing_id);
CREATE INDEX kennel_types_active_idx ON kennel_types(listing_id) WHERE active;

CREATE INDEX bookings_owner_id_idx ON bookings(owner_id);
CREATE INDEX bookings_business_id_idx ON bookings(business_id);
CREATE INDEX bookings_kennel_type_status_idx ON bookings(kennel_type_id, status);
CREATE INDEX bookings_status_requested_idx ON bookings(status, requested_at) WHERE status = 'requested';
CREATE INDEX bookings_status_payment_deadline_idx ON bookings(status, payment_deadline) WHERE status IN ('accepted','pending_payment');
CREATE INDEX bookings_status_check_out_idx ON bookings(status, check_out) WHERE status = 'confirmed';

CREATE INDEX booking_pets_booking_id_idx ON booking_pets(booking_id);

CREATE INDEX notifications_user_created_idx ON notifications(user_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications(user_id) WHERE read_at IS NULL;

CREATE INDEX peak_calendar_date_idx ON peak_calendar(date);
CREATE INDEX availability_overrides_kennel_date_idx ON availability_overrides(kennel_type_id, date);

-- Review lookups by business (dashboard queries, public listing page)
CREATE INDEX reviews_business_id_idx ON reviews(business_id);
CREATE INDEX review_responses_business_id_idx ON review_responses(business_id);

-- Booking lookups by listing (dashboard "show all bookings for this listing" queries)
CREATE INDEX bookings_listing_id_idx ON bookings(listing_id);
