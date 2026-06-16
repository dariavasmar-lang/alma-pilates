-- ============================================================
-- Migration: add 'unpaid_future' to bookings.status
-- Run on existing PROD and DEV databases
-- ============================================================

-- 1. Drop old CHECK constraint and add new one with 'unpaid_future'
ALTER TABLE bookings
  DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE bookings
  ADD CONSTRAINT bookings_status_check
  CHECK (status IN ('booked','attended','missed','cancelled','unpaid_future'));

-- 2. Backfill: existing bookings after subscription.expires_at → 'unpaid_future'
--    These were previously inserted as 'booked' with subscription_id=NULL
--    and class_date > subscription period
UPDATE bookings b
SET status = 'unpaid_future', subscription_id = NULL
WHERE b.status = 'booked'
  AND b.subscription_id IS NULL
  AND EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.client_id = b.client_id
      AND s.is_active = true
      AND b.class_date > s.expires_at
  );
