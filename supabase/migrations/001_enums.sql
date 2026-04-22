-- User role for user_profiles.primary_role
CREATE TYPE user_role AS ENUM (
  'owner',
  'business_admin',
  'platform_admin'
);

-- Business lifecycle
CREATE TYPE kyc_status AS ENUM (
  'pending',
  'verified',
  'rejected'
);

CREATE TYPE business_status AS ENUM (
  'active',
  'paused',
  'banned'
);

-- Animal species accepted by a kennel type
CREATE TYPE species_accepted AS ENUM (
  'dog',
  'cat',
  'both'
);

CREATE TYPE species AS ENUM (
  'dog',
  'cat'
);

CREATE TYPE size_range AS ENUM (
  'small',
  'medium',
  'large'
);

-- Per-listing cancellation policy
CREATE TYPE cancellation_policy AS ENUM (
  'flexible',
  'moderate',
  'strict'
);

-- Booking state machine (see spec §7)
CREATE TYPE booking_status AS ENUM (
  'requested',
  'accepted',
  'declined',
  'pending_payment',
  'expired',
  'confirmed',
  'completed',
  'cancelled_by_owner',
  'cancelled_by_business'
);

-- Reason a booking reached a terminal state
CREATE TYPE booking_terminal_reason AS ENUM (
  'no_response_24h',
  'no_payment_24h',
  'no_payment_15min_instant',
  'owner_cancelled',
  'business_cancelled',
  'payment_failed'
);

-- Notification kinds (in-app feed)
CREATE TYPE notification_kind AS ENUM (
  'request_submitted',
  'request_accepted',
  'request_declined',
  'payment_confirmed',
  'acceptance_expiring',
  'payment_expiring',
  'booking_cancelled',
  'review_prompt',
  'review_received'
);
