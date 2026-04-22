-- Peak dates. Platform rows have business_id = NULL; businesses layer overrides on top.
CREATE TABLE peak_calendar (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid REFERENCES businesses(id) ON DELETE CASCADE,
  date date NOT NULL,
  label text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One entry per (business_id, date) pair; NULL business_id is the platform row.
CREATE UNIQUE INDEX peak_calendar_global_uidx
  ON peak_calendar (date)
  WHERE business_id IS NULL;

CREATE UNIQUE INDEX peak_calendar_business_uidx
  ON peak_calendar (business_id, date)
  WHERE business_id IS NOT NULL;

-- Manual blocks by a business on a specific kennel+date.
CREATE TABLE availability_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kennel_type_id uuid NOT NULL REFERENCES kennel_types(id) ON DELETE CASCADE,
  date date NOT NULL,
  manual_block boolean NOT NULL DEFAULT true,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kennel_type_id, date)
);
