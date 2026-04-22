-- Is a date peak for this business? Platform peak_calendar row (business_id=NULL)
-- OR a business-specific override row counts.
CREATE OR REPLACE FUNCTION is_peak_date(p_business_id uuid, p_date date)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM peak_calendar
    WHERE date = p_date
      AND (business_id IS NULL OR business_id = p_business_id)
  );
$$;

-- Compute subtotal for a stay. Sums per-night prices based on peak/off-peak.
-- check_out is exclusive (same semantics as bookings.nights).
CREATE OR REPLACE FUNCTION compute_stay_subtotal(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date
) RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_biz uuid;
  v_base numeric;
  v_peak numeric;
  v_total numeric := 0;
  v_d date := p_check_in;
BEGIN
  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  SELECT l.business_id, kt.base_price_myr, kt.peak_price_myr
    INTO v_biz, v_base, v_peak
    FROM kennel_types kt JOIN listings l ON l.id = kt.listing_id
    WHERE kt.id = p_kennel_type_id;

  IF v_biz IS NULL THEN
    RAISE EXCEPTION 'kennel_type_id % not found', p_kennel_type_id;
  END IF;

  WHILE v_d < p_check_out LOOP
    v_total := v_total + CASE WHEN is_peak_date(v_biz, v_d) THEN v_peak ELSE v_base END;
    v_d := v_d + 1;
  END LOOP;

  RETURN v_total;
END;
$$;

-- How many of a kennel type are occupied on any day in [check_in, check_out)?
-- Considers bookings in active states (accepted, pending_payment, confirmed) and manual blocks.
CREATE OR REPLACE FUNCTION kennel_occupied_count(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date
) RETURNS integer
LANGUAGE sql STABLE
AS $$
  WITH day_range AS (
    SELECT generate_series(p_check_in, p_check_out - 1, '1 day'::interval)::date AS d
  ),
  occupied AS (
    SELECT d, (
      SELECT count(*)::int FROM bookings b
      WHERE b.kennel_type_id = p_kennel_type_id
        AND b.status IN ('accepted','pending_payment','confirmed')
        AND d >= b.check_in AND d < b.check_out
    ) + (
      SELECT count(*)::int FROM availability_overrides ao
      WHERE ao.kennel_type_id = p_kennel_type_id
        AND ao.date = d AND ao.manual_block
    ) AS cnt
    FROM day_range
  )
  SELECT COALESCE(max(cnt), 0) FROM occupied;
$$;

-- Is at least p_needed units of the kennel available throughout [check_in, check_out)?
CREATE OR REPLACE FUNCTION kennel_available(
  p_kennel_type_id uuid,
  p_check_in date,
  p_check_out date,
  p_needed integer
) RETURNS boolean
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_cap integer;
  v_occ integer;
BEGIN
  SELECT capacity INTO v_cap FROM kennel_types WHERE id = p_kennel_type_id AND active;
  IF v_cap IS NULL THEN RETURN false; END IF;
  v_occ := kennel_occupied_count(p_kennel_type_id, p_check_in, p_check_out);
  RETURN (v_cap - v_occ) >= p_needed;
END;
$$;

-- Does this pet have a cert valid for the whole stay?
CREATE OR REPLACE FUNCTION pet_has_valid_cert(
  p_pet_id uuid,
  p_check_out date
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vaccination_certs
    WHERE pet_id = p_pet_id AND expires_on >= p_check_out
  );
$$;
