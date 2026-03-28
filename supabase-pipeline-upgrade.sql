-- ============================================================
-- Pipeline Upgrade: Add country gate + 5-stage qualification
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor AFTER the original setup.
-- Safe to run multiple times — all statements are idempotent.
-- ============================================================

-- ── Add new columns for country qualification gate ──
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS country TEXT DEFAULT '';
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS pain_signal BOOLEAN;
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS urgency_signal BOOLEAN;
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS income_signal BOOLEAN;
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS qual_score INTEGER;
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS break_reason TEXT DEFAULT '';
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS approach_used TEXT DEFAULT '';
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS stage_entered_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS content_format TEXT DEFAULT '';
ALTER TABLE pipeline_leads ADD COLUMN IF NOT EXISTS call_outcome TEXT DEFAULT '';

-- ── Update status CHECK constraint to allow new stage values ──
-- Drop the old constraint (safe — does nothing if already dropped)
ALTER TABLE pipeline_leads DROP CONSTRAINT IF EXISTS pipeline_leads_status_check;

-- Add updated constraint that allows both old and new status values
ALTER TABLE pipeline_leads ADD CONSTRAINT pipeline_leads_status_check
  CHECK (status IN (
    -- New 5-stage values
    'new', 'qualifying', 'hot', 'booked', 'dead',
    -- Legacy values (for backward compatibility with existing data)
    'in_conversation', 'completed_call', 'closed_won', 'closed_lost',
    'ghosted', 'not_qualified', 'no_show'
  ));

-- ── Index for country-based filtering ──
CREATE INDEX IF NOT EXISTS idx_pl_country ON pipeline_leads(country);

-- ============================================================
-- DONE! Your pipeline now supports:
--   - Country qualification (country column)
--   - 5-stage workflow (new/qualifying/hot/booked/dead)
--   - Qualification signals (pain/urgency/income)
--   - Break reasons and booking approaches
--   - Content format tracking
--   - Call outcome tracking
-- ============================================================
