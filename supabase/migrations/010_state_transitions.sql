-- create_booking_request: request-to-book path.
-- Preconditions:
--   - caller owns every pet in p_pet_ids
--   - kennel is active and NOT instant_book
--   - each pet has a vaccination cert valid through check_out
--   - capacity - current occupancy - manual blocks >= 1 across [check_in, check_out)
-- Effect: inserts booking with status='requested', acceptance deadline = now()+24h.
CREATE OR REPLACE FUNCTION create_booking_request(
  p_kennel_type_id uuid,
  p_pet_ids uuid[],
  p_check_in date,
  p_check_out date,
  p_special_instructions text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_kennel kennel_types%ROWTYPE;
  v_business_id uuid;
  v_listing_id uuid;
  v_nights integer;
  v_subtotal numeric;
  v_platform_fee numeric;
  v_booking_id uuid;
  v_pet_id uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is null; must be called by an authenticated user';
  END IF;

  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  IF array_length(p_pet_ids, 1) IS NULL OR array_length(p_pet_ids, 1) = 0 THEN
    RAISE EXCEPTION 'at least one pet required';
  END IF;

  -- Lock the kennel row for the duration of the tx so racing requests serialize
  SELECT * INTO v_kennel FROM kennel_types WHERE id = p_kennel_type_id AND active FOR UPDATE;
  IF v_kennel IS NULL THEN
    RAISE EXCEPTION 'kennel_type % is not active or not found', p_kennel_type_id;
  END IF;

  IF v_kennel.instant_book THEN
    RAISE EXCEPTION 'kennel is instant_book; use create_instant_booking instead';
  END IF;

  SELECT l.id, l.business_id INTO v_listing_id, v_business_id
    FROM listings l WHERE l.id = v_kennel.listing_id;

  -- Every pet must belong to the caller
  FOREACH v_pet_id IN ARRAY p_pet_ids LOOP
    PERFORM 1 FROM pets WHERE id = v_pet_id AND owner_id = v_owner_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'pet % does not belong to caller', v_pet_id;
    END IF;
    IF NOT pet_has_valid_cert(v_pet_id, p_check_out) THEN
      RAISE EXCEPTION 'pet % has no valid vaccination cert for this stay', v_pet_id
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  IF NOT kennel_available(p_kennel_type_id, p_check_in, p_check_out, 1) THEN
    RAISE EXCEPTION 'kennel_type % not available for % to %', p_kennel_type_id, p_check_in, p_check_out;
  END IF;

  v_nights := (p_check_out - p_check_in);
  v_subtotal := compute_stay_subtotal(p_kennel_type_id, p_check_in, p_check_out);

  -- Commission: resolved from business.commission_rate_bps (defaults to 1200 = 12%)
  v_platform_fee := round(v_subtotal * (
    (SELECT commission_rate_bps FROM businesses WHERE id = v_business_id) / 10000.0
  ), 2);

  INSERT INTO bookings (
    owner_id, business_id, listing_id, kennel_type_id,
    check_in, check_out, nights,
    subtotal_myr, platform_fee_myr, business_payout_myr,
    status, special_instructions, payment_deadline
  )
  VALUES (
    v_owner_id, v_business_id, v_listing_id, p_kennel_type_id,
    p_check_in, p_check_out, v_nights,
    v_subtotal, v_platform_fee, v_subtotal - v_platform_fee,
    'requested', p_special_instructions, now() + interval '24 hours'
  )
  RETURNING id INTO v_booking_id;

  -- booking_pets
  INSERT INTO booking_pets (booking_id, pet_id)
  SELECT v_booking_id, unnest(p_pet_ids);

  -- Cert snapshots (latest cert per pet)
  INSERT INTO booking_cert_snapshots (booking_id, pet_id, vaccination_cert_id, file_url, expires_on)
  SELECT v_booking_id, vc.pet_id, vc.id, vc.file_url, vc.expires_on
  FROM vaccination_certs vc
  WHERE vc.pet_id = ANY(p_pet_ids)
    AND vc.id = (
      SELECT id FROM vaccination_certs vc2
      WHERE vc2.pet_id = vc.pet_id
      ORDER BY expires_on DESC LIMIT 1
    );

  -- Notify owner + business admins
  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_owner_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id));

  INSERT INTO notifications (user_id, kind, payload)
  SELECT bm.user_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id)
  FROM business_members bm WHERE bm.business_id = v_business_id;

  RETURN v_booking_id;
END;
$$;

-- accept_booking: business_admin transitions requested -> accepted
-- Sets payment_deadline = now() + 24h
CREATE OR REPLACE FUNCTION accept_booking(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id;
  END IF;
  IF NOT is_business_member(v_row.business_id) THEN
    RAISE EXCEPTION 'not a member of owning business';
  END IF;
  IF v_row.status != 'requested' THEN
    RAISE EXCEPTION 'booking % not in requested state (is %)', p_booking_id, v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'accepted',
    acted_at = now(),
    payment_deadline = now() + interval '24 hours'
  WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'request_accepted', jsonb_build_object('booking_id', p_booking_id));
END;
$$;

-- decline_booking: business_admin transitions requested -> declined
CREATE OR REPLACE FUNCTION decline_booking(p_booking_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'booking % not found', p_booking_id;
  END IF;
  IF NOT is_business_member(v_row.business_id) THEN
    RAISE EXCEPTION 'not a member of owning business';
  END IF;
  IF v_row.status != 'requested' THEN
    RAISE EXCEPTION 'booking % not in requested state (is %)', p_booking_id, v_row.status;
  END IF;

  UPDATE bookings SET
    status = 'declined',
    acted_at = now(),
    special_instructions = COALESCE(special_instructions, '') ||
      CASE WHEN p_reason IS NOT NULL THEN E'\n[decline reason] ' || p_reason ELSE '' END
  WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'request_declined', jsonb_build_object('booking_id', p_booking_id, 'reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION create_instant_booking(
  p_kennel_type_id uuid,
  p_pet_ids uuid[],
  p_check_in date,
  p_check_out date,
  p_special_instructions text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_kennel kennel_types%ROWTYPE;
  v_business_id uuid;
  v_listing_id uuid;
  v_nights integer;
  v_subtotal numeric;
  v_platform_fee numeric;
  v_booking_id uuid;
  v_pet_id uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is null';
  END IF;

  IF p_check_out <= p_check_in THEN
    RAISE EXCEPTION 'check_out must be after check_in';
  END IF;

  IF array_length(p_pet_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'at least one pet required';
  END IF;

  SELECT * INTO v_kennel FROM kennel_types WHERE id = p_kennel_type_id AND active FOR UPDATE;
  IF v_kennel IS NULL THEN
    RAISE EXCEPTION 'kennel_type % not active/found', p_kennel_type_id;
  END IF;

  IF NOT v_kennel.instant_book THEN
    RAISE EXCEPTION 'kennel is not instant_book; use create_booking_request';
  END IF;

  SELECT l.id, l.business_id INTO v_listing_id, v_business_id
    FROM listings l WHERE l.id = v_kennel.listing_id;

  FOREACH v_pet_id IN ARRAY p_pet_ids LOOP
    PERFORM 1 FROM pets WHERE id = v_pet_id AND owner_id = v_owner_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'pet % not owned by caller', v_pet_id; END IF;
    IF NOT pet_has_valid_cert(v_pet_id, p_check_out) THEN
      RAISE EXCEPTION 'pet % has no valid cert', v_pet_id USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  IF NOT kennel_available(p_kennel_type_id, p_check_in, p_check_out, 1) THEN
    RAISE EXCEPTION 'kennel not available for %..%', p_check_in, p_check_out;
  END IF;

  v_nights := (p_check_out - p_check_in);
  v_subtotal := compute_stay_subtotal(p_kennel_type_id, p_check_in, p_check_out);
  v_platform_fee := round(v_subtotal * (
    (SELECT commission_rate_bps FROM businesses WHERE id = v_business_id) / 10000.0
  ), 2);

  INSERT INTO bookings (
    owner_id, business_id, listing_id, kennel_type_id,
    check_in, check_out, nights,
    subtotal_myr, platform_fee_myr, business_payout_myr,
    status, special_instructions, payment_deadline, acted_at
  )
  VALUES (
    v_owner_id, v_business_id, v_listing_id, p_kennel_type_id,
    p_check_in, p_check_out, v_nights,
    v_subtotal, v_platform_fee, v_subtotal - v_platform_fee,
    'pending_payment', p_special_instructions,
    now() + interval '15 minutes', now()
  )
  RETURNING id INTO v_booking_id;

  INSERT INTO booking_pets (booking_id, pet_id)
  SELECT v_booking_id, unnest(p_pet_ids);

  INSERT INTO booking_cert_snapshots (booking_id, pet_id, vaccination_cert_id, file_url, expires_on)
  SELECT v_booking_id, vc.pet_id, vc.id, vc.file_url, vc.expires_on
  FROM vaccination_certs vc
  WHERE vc.pet_id = ANY(p_pet_ids)
    AND vc.id = (SELECT id FROM vaccination_certs WHERE pet_id = vc.pet_id
                 ORDER BY expires_on DESC LIMIT 1);

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_owner_id, 'request_submitted', jsonb_build_object('booking_id', v_booking_id, 'instant', true));

  RETURN v_booking_id;
END;
$$;

-- create_payment_intent: caller (owner) gets a ref_no for the booking.
-- Booking must be in 'accepted' or 'pending_payment'. Freezes the amount.
CREATE OR REPLACE FUNCTION create_payment_intent(p_booking_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
  v_ref text;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_row IS NULL THEN RAISE EXCEPTION 'booking not found'; END IF;
  IF v_row.owner_id != auth.uid() THEN
    RAISE EXCEPTION 'only booking owner can create payment intent';
  END IF;
  IF v_row.status NOT IN ('accepted','pending_payment') THEN
    RAISE EXCEPTION 'booking % not payable (is %)', p_booking_id, v_row.status;
  END IF;
  IF v_row.payment_deadline < now() THEN
    RAISE EXCEPTION 'payment deadline passed';
  END IF;

  -- If a ref was already issued, return it (idempotent)
  IF v_row.ipay88_reference IS NOT NULL THEN
    RETURN v_row.ipay88_reference;
  END IF;

  -- Ref format: PETBNB-<8-char uid>-<booking short>
  v_ref := 'PETBNB-' || substr(replace(gen_random_uuid()::text,'-',''),1,8) || '-'
           || substr(p_booking_id::text, 1, 8);

  -- If booking was 'accepted', transition to 'pending_payment'
  UPDATE bookings SET
    ipay88_reference = v_ref,
    status = CASE WHEN status = 'accepted' THEN 'pending_payment'::booking_status ELSE status END
  WHERE id = p_booking_id;

  RETURN v_ref;
END;
$$;

-- confirm_payment: called by the iPay88 webhook Edge Function.
-- Idempotent by ref_no. Only transitions pending_payment -> confirmed.
-- Takes received_amount so we can detect tampering (iPay88 tells us what was charged).
CREATE OR REPLACE FUNCTION confirm_payment(p_ref text, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE ipay88_reference = p_ref FOR UPDATE;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'no booking with reference %', p_ref;
  END IF;

  -- Idempotent: already confirmed, do nothing
  IF v_row.status = 'confirmed' THEN
    RETURN;
  END IF;

  IF v_row.status != 'pending_payment' THEN
    RAISE EXCEPTION 'booking for ref % not in pending_payment (is %)', p_ref, v_row.status;
  END IF;

  -- Amount must match subtotal to the cent
  IF abs(p_amount - v_row.subtotal_myr) > 0.01 THEN
    RAISE EXCEPTION 'amount mismatch: expected %, got %', v_row.subtotal_myr, p_amount;
  END IF;

  UPDATE bookings SET
    status = 'confirmed',
    acted_at = now()
  WHERE id = v_row.id;

  INSERT INTO notifications (user_id, kind, payload)
  VALUES (v_row.owner_id, 'payment_confirmed', jsonb_build_object('booking_id', v_row.id, 'ref', p_ref));

  INSERT INTO notifications (user_id, kind, payload)
  SELECT bm.user_id, 'payment_confirmed', jsonb_build_object('booking_id', v_row.id, 'ref', p_ref)
  FROM business_members bm WHERE bm.business_id = v_row.business_id;
END;
$$;
