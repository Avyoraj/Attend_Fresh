-- =============================================
-- Add step2_verified status + step2_verified_at column
-- Step-2 pass no longer means "confirmed" — analysis does that.
-- =============================================

-- 1. Drop old CHECK constraint and add new one with step2_verified
ALTER TABLE attendance DROP CONSTRAINT IF EXISTS attendance_status_check;
ALTER TABLE attendance ADD CONSTRAINT attendance_status_check
  CHECK (status IN ('provisional', 'step2_verified', 'flagged', 'pending_physical', 'confirmed', 'cancelled', 'manual', 'absent'));

-- 2. Add timestamp column for step-2 verification
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS step2_verified_at TIMESTAMPTZ;
