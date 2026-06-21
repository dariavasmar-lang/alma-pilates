-- ============================================================
-- Migration: add subscription types '4' and '12s', add is_trial to clients
-- Run on PROD Supabase before deploying the new frontend
-- ============================================================

-- 1. Update subscriptions type constraint to include new types
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_type_check;
ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_type_check
  CHECK (type IN ('4','8','12','12s','single'));

-- 2. Add is_trial flag to clients (for free trial tracking, no subscription)
ALTER TABLE clients ADD COLUMN IF NOT EXISTS is_trial boolean DEFAULT false;
