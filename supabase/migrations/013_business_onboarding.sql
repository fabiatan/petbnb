-- create_business_onboarding: the only supported path for creating a new
-- business. RLS on businesses + business_members both require caller to be a
-- member; this function bypasses those (SECURITY DEFINER) and atomically
-- creates business + member + stub listing in one transaction.
CREATE OR REPLACE FUNCTION create_business_onboarding(
  p_name text,
  p_slug text,
  p_address text,
  p_city text,
  p_state text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_biz_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'must be authenticated';
  END IF;

  -- Caller must have a user_profile row (sign-up flow inserts this)
  PERFORM 1 FROM user_profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user_profile missing for uid %', v_uid;
  END IF;

  -- Basic input validation
  IF coalesce(length(trim(p_name)), 0) = 0 THEN
    RAISE EXCEPTION 'name cannot be empty';
  END IF;
  IF coalesce(length(trim(p_slug)), 0) = 0 THEN
    RAISE EXCEPTION 'slug cannot be empty';
  END IF;
  IF p_slug !~ '^[a-z0-9-]+$' THEN
    RAISE EXCEPTION 'slug must be lowercase alphanumeric with hyphens only';
  END IF;

  -- Insert business (will raise unique_violation on duplicate slug)
  INSERT INTO businesses (name, slug, address, city, state)
  VALUES (trim(p_name), lower(p_slug), trim(p_address), trim(p_city), trim(p_state))
  RETURNING id INTO v_biz_id;

  -- Make caller an admin
  INSERT INTO business_members (business_id, user_id, role)
  VALUES (v_biz_id, v_uid, 'admin');

  -- Stub listing (one listing per business — MVP rule)
  INSERT INTO listings (business_id)
  VALUES (v_biz_id);

  -- Flip the user's role to business_admin if they weren't already
  UPDATE user_profiles SET primary_role = 'business_admin'
  WHERE id = v_uid AND primary_role = 'owner';

  RETURN v_biz_id;
END;
$$;

-- Expose to authenticated users (service_role already has all privileges)
GRANT EXECUTE ON FUNCTION create_business_onboarding(text,text,text,text,text) TO authenticated;
