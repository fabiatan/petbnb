-- Expire requested bookings older than 24h
CREATE OR REPLACE FUNCTION sweep_expire_stale_requests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE bookings SET
      status = 'expired',
      terminal_reason = 'no_response_24h',
      acted_at = now()
    WHERE status = 'requested'
      AND requested_at < now() - interval '24 hours'
    RETURNING id, owner_id
  ), notify AS (
    INSERT INTO notifications (user_id, kind, payload)
    SELECT owner_id, 'booking_cancelled',
      jsonb_build_object('booking_id', id, 'reason','request_timed_out')
    FROM expired
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$$;

-- Expire accepted/pending_payment bookings past their payment_deadline
CREATE OR REPLACE FUNCTION sweep_expire_stale_payments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  UPDATE bookings SET
    status = 'expired',
    terminal_reason = (CASE WHEN is_instant_book
                            THEN 'no_payment_15min_instant'
                            ELSE 'no_payment_24h' END)::booking_terminal_reason,
    acted_at = now()
  WHERE status IN ('accepted','pending_payment')
    AND payment_deadline < now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Complete bookings whose check_out is in the past
CREATE OR REPLACE FUNCTION sweep_complete_past_bookings()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count integer;
BEGIN
  WITH done AS (
    UPDATE bookings SET
      status = 'completed',
      acted_at = now()
    WHERE status = 'confirmed'
      AND check_out < CURRENT_DATE
    RETURNING id, owner_id
  ), notify AS (
    INSERT INTO notifications (user_id, kind, payload)
    SELECT owner_id, 'review_prompt', jsonb_build_object('booking_id', id)
    FROM done
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM done;
  RETURN v_count;
END;
$$;

-- Phase 0 stub: Phase 3 wires iPay88 lookup API.
CREATE OR REPLACE FUNCTION sweep_reconcile_pending_payments()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Intentionally empty in Phase 0. Phase 3: call iPay88 lookup for each
  -- pending_payment >20m old, compare with their record, reconcile.
  RETURN 0;
END;
$$;

-- Schedule via pg_cron (all times in UTC; Supabase pg_cron uses UTC)
-- Only schedule if pg_cron extension is available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedule any existing PetBnB jobs first (idempotent re-apply)
    PERFORM cron.unschedule(jobid) FROM cron.job
      WHERE jobname IN (
        'petbnb_expire_requests','petbnb_expire_payments',
        'petbnb_complete_past','petbnb_reconcile_payments'
      );

    PERFORM cron.schedule('petbnb_expire_requests',  '*/5 * * * *',  'SELECT sweep_expire_stale_requests();');
    PERFORM cron.schedule('petbnb_expire_payments',  '*/5 * * * *',  'SELECT sweep_expire_stale_payments();');
    PERFORM cron.schedule('petbnb_complete_past',    '5 16 * * *',   'SELECT sweep_complete_past_bookings();'); -- 00:05 MY = 16:05 UTC
    PERFORM cron.schedule('petbnb_reconcile_payments','*/30 * * * *','SELECT sweep_reconcile_pending_payments();');
  END IF;
END $$;
