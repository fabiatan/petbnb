CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES businesses(id),
  owner_id uuid NOT NULL REFERENCES user_profiles(id),
  service_rating integer NOT NULL CHECK (service_rating BETWEEN 1 AND 5),
  response_rating integer NOT NULL CHECK (response_rating BETWEEN 1 AND 5),
  text text,
  posted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL UNIQUE REFERENCES reviews(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES businesses(id),
  text text NOT NULL,
  posted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  kind notification_kind NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
