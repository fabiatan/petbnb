CREATE TABLE bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES user_profiles(id),
  business_id uuid NOT NULL REFERENCES businesses(id),
  listing_id uuid NOT NULL REFERENCES listings(id),
  kennel_type_id uuid NOT NULL REFERENCES kennel_types(id),
  check_in date NOT NULL,
  check_out date NOT NULL,
  nights integer NOT NULL,
  subtotal_myr numeric(10,2) NOT NULL CHECK (subtotal_myr >= 0),
  platform_fee_myr numeric(10,2) NOT NULL DEFAULT 0 CHECK (platform_fee_myr >= 0),
  business_payout_myr numeric(10,2) NOT NULL DEFAULT 0 CHECK (business_payout_myr >= 0),
  status booking_status NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  acted_at timestamptz,
  payment_deadline timestamptz,
  special_instructions text,
  terminal_reason booking_terminal_reason,
  ipay88_reference text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (check_out > check_in),
  CHECK (nights = (check_out - check_in))
);

CREATE TRIGGER set_updated_at_bookings
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- Pets covered by a booking (many-to-many)
CREATE TABLE booking_pets (
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  pet_id uuid NOT NULL REFERENCES pets(id),
  PRIMARY KEY (booking_id, pet_id)
);

-- Frozen vaccination cert references per booking
CREATE TABLE booking_cert_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  pet_id uuid NOT NULL REFERENCES pets(id),
  vaccination_cert_id uuid NOT NULL REFERENCES vaccination_certs(id),
  file_url text NOT NULL,
  expires_on date NOT NULL,
  snapshotted_at timestamptz NOT NULL DEFAULT now()
);
