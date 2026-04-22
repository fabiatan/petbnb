-- user_profiles: extends auth.users with app-level fields
CREATE TABLE user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  avatar_url text,
  phone text,
  preferred_lang text NOT NULL DEFAULT 'en' CHECK (preferred_lang IN ('en','ms','zh')),
  primary_role user_role NOT NULL DEFAULT 'owner',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- pets: owned by a user_profile
CREATE TABLE pets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  species species NOT NULL,
  breed text,
  age_months integer CHECK (age_months >= 0 AND age_months < 600),
  weight_kg numeric(5,2) CHECK (weight_kg > 0 AND weight_kg < 200),
  medical_notes text,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- vaccination_certs: file reference + expiry
CREATE TABLE vaccination_certs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pet_id uuid NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
  file_url text NOT NULL,
  vaccines_covered text[] NOT NULL DEFAULT ARRAY[]::text[],
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  verified_by_business_id uuid,    -- FK added in 003; deferred to avoid circular order
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on > issued_on)
);

-- Auto-update updated_at on user_profiles and pets
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_user_profiles
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_pets
  BEFORE UPDATE ON pets
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
