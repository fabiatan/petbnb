CREATE TABLE businesses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  geo_point point,
  description text,
  cover_photo_url text,
  logo_url text,
  kyc_status kyc_status NOT NULL DEFAULT 'pending',
  kyc_documents jsonb NOT NULL DEFAULT '{}'::jsonb,
  commission_rate_bps integer NOT NULL DEFAULT 1200 CHECK (commission_rate_bps BETWEEN 0 AND 10000),
  payout_bank_info jsonb NOT NULL DEFAULT '{}'::jsonb,    -- Phase 5: wrap with pgsodium before real payouts
  status business_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_businesses
  BEFORE UPDATE ON businesses
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- business_members: join table (user <-> business)
CREATE TABLE business_members (
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'admin' CHECK (role IN ('admin')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, user_id)
);

-- listings: one per business (for MVP)
CREATE TABLE listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL UNIQUE REFERENCES businesses(id) ON DELETE CASCADE,
  photos text[] NOT NULL DEFAULT ARRAY[]::text[],
  amenities text[] NOT NULL DEFAULT ARRAY[]::text[],
  house_rules text,
  cancellation_policy cancellation_policy NOT NULL DEFAULT 'moderate',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_listings
  BEFORE UPDATE ON listings
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- kennel_types: variants inside a listing
CREATE TABLE kennel_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  name text NOT NULL,
  species_accepted species_accepted NOT NULL,
  size_range size_range NOT NULL,
  capacity integer NOT NULL CHECK (capacity > 0),
  base_price_myr numeric(10,2) NOT NULL CHECK (base_price_myr >= 0),
  peak_price_myr numeric(10,2) NOT NULL CHECK (peak_price_myr >= 0),
  instant_book boolean NOT NULL DEFAULT false,
  description text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_kennel_types
  BEFORE UPDATE ON kennel_types
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- Add the deferred FK from vaccination_certs -> businesses
ALTER TABLE vaccination_certs
  ADD CONSTRAINT vaccination_certs_verified_by_business_id_fkey
  FOREIGN KEY (verified_by_business_id) REFERENCES businesses(id) ON DELETE SET NULL;
