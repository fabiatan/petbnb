-- Phase 2d: fix confirm_payment to work with PostgREST 14's JWT claim format.
--
-- PostgREST ≤12 set individual GUCs: request.jwt.claim.role
-- PostgREST 14 (bundled with Supabase CLI 2.x) sets the full claims as JSON:
--   request.jwt.claims  →  '{"iss":"...","role":"service_role","exp":...}'
-- The old check (request.jwt.claim.role) always evaluates to null, so the
-- service_role guard always fires and blocks the Edge Function webhook.
-- This migration updates the check to read from request.jwt.claims JSON.

CREATE OR REPLACE FUNCTION public.confirm_payment(p_ref text, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row bookings%ROWTYPE;
  v_jwt_role text;
BEGIN
  -- PostgREST 14 stores JWT claims as a JSON string in request.jwt.claims.
  -- Older versions stored them as individual GUCs (request.jwt.claim.role).
  -- We try the JSON path first, fall back to the legacy GUC.
  v_jwt_role := COALESCE(
    current_setting('request.jwt.claims', true)::jsonb ->> 'role',
    current_setting('request.jwt.claim.role', true)
  );

  IF v_jwt_role IS DISTINCT FROM 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'confirm_payment may only be called by service_role';
  END IF;

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
