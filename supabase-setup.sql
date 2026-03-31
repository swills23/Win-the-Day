-- ============================================================
-- Win the Day — Pipeline Automation: Supabase Setup
-- ============================================================
-- Run this ENTIRE script in your Supabase Dashboard:
--   1. Go to https://supabase.com/dashboard
--   2. Select your project
--   3. Click "SQL Editor" in the left sidebar
--   4. Paste this entire file and click "Run"
-- ============================================================

-- ── STEP 1: Create pipeline_leads table ──
CREATE TABLE IF NOT EXISTS pipeline_leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL DEFAULT '',
  ig_handle TEXT DEFAULT '',
  source_keyword TEXT DEFAULT '',
  source_type TEXT DEFAULT 'other',
  lead_source TEXT DEFAULT '',
  dm_date TIMESTAMPTZ DEFAULT now(),
  first_reply_at TIMESTAMPTZ,
  status TEXT DEFAULT 'new' CHECK (status IN ('new','in_conversation','booked','no_show','completed_call','closed_won','closed_lost','ghosted','not_qualified')),
  lead_quality TEXT DEFAULT 'warm' CHECK (lead_quality IN ('hot','warm','cold')),
  setter TEXT DEFAULT '',
  setter_notes TEXT DEFAULT '',
  objections TEXT DEFAULT '',
  objection_categories TEXT[] DEFAULT '{}',
  outcome_notes TEXT DEFAULT '',
  booked_date TIMESTAMPTZ,
  touchpoints INTEGER DEFAULT 0,
  followups JSONB DEFAULT '[]',
  mc_subscriber_id TEXT DEFAULT '',
  mc_tags TEXT[] DEFAULT '{}',
  mc_email TEXT DEFAULT '',
  mc_source TEXT DEFAULT 'manual',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_pl_owner ON pipeline_leads(owner_id);
CREATE INDEX IF NOT EXISTS idx_pl_status ON pipeline_leads(status);
CREATE INDEX IF NOT EXISTS idx_pl_mc_sub ON pipeline_leads(mc_subscriber_id);
CREATE INDEX IF NOT EXISTS idx_pl_dm_date ON pipeline_leads(dm_date DESC);

-- ── STEP 2: Row Level Security ──
ALTER TABLE pipeline_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own leads" ON pipeline_leads
  FOR SELECT USING (auth.uid() = owner_id);

CREATE POLICY "Users insert own leads" ON pipeline_leads
  FOR INSERT WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users update own leads" ON pipeline_leads
  FOR UPDATE USING (auth.uid() = owner_id);

CREATE POLICY "Users delete own leads" ON pipeline_leads
  FOR DELETE USING (auth.uid() = owner_id);

-- ── STEP 3: Webhook receiver function ──
-- ManyChat calls this via External Request to auto-import leads.
-- SECURITY DEFINER bypasses RLS since webhooks have no auth token.
CREATE OR REPLACE FUNCTION receive_manychat_lead(
  webhook_secret TEXT,
  subscriber_id TEXT,
  subscriber_name TEXT,
  ig_username TEXT DEFAULT '',
  email TEXT DEFAULT '',
  tags TEXT DEFAULT '',
  lead_source TEXT DEFAULT 'dm_first',
  source_keyword TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  -- SECURITY: Read secret from Supabase config, not hardcoded
  -- Set via: ALTER DATABASE postgres SET app.manychat_webhook_secret = 'your-secret-here';
  expected_secret TEXT := coalesce(current_setting('app.manychat_webhook_secret', true), '');
  admin_user_id UUID;
  existing_lead UUID;
  new_lead_id UUID;
  tag_array TEXT[];
BEGIN
  -- Validate webhook secret
  IF webhook_secret != expected_secret THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Invalid secret');
  END IF;

  -- Find admin user (Scott)
  SELECT id INTO admin_user_id
  FROM auth.users
  WHERE email = 'scott@scottzwills.com'
  LIMIT 1;

  IF admin_user_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Admin not found');
  END IF;

  -- Parse tags (comma-separated string from ManyChat)
  IF tags IS NOT NULL AND tags != '' THEN
    tag_array := string_to_array(tags, ',');
  ELSE
    tag_array := '{}';
  END IF;

  -- Check for duplicate by mc_subscriber_id
  SELECT id INTO existing_lead
  FROM pipeline_leads
  WHERE mc_subscriber_id = subscriber_id AND owner_id = admin_user_id
  LIMIT 1;

  IF existing_lead IS NOT NULL THEN
    -- Update existing lead with fresh data
    UPDATE pipeline_leads SET
      mc_tags = tag_array,
      mc_email = COALESCE(NULLIF(email, ''), mc_email),
      ig_handle = COALESCE(NULLIF(ig_username, ''), ig_handle),
      updated_at = now()
    WHERE id = existing_lead;

    RETURN jsonb_build_object('status', 'ok', 'action', 'updated', 'lead_id', existing_lead);
  END IF;

  -- Insert new lead
  INSERT INTO pipeline_leads (
    owner_id, name, ig_handle, lead_source, source_keyword,
    source_type, dm_date, status, lead_quality,
    mc_subscriber_id, mc_tags, mc_email, mc_source
  ) VALUES (
    admin_user_id,
    subscriber_name,
    COALESCE(NULLIF(ig_username, ''), ''),
    COALESCE(NULLIF(receive_manychat_lead.lead_source, ''), 'dm_first'),
    COALESCE(NULLIF(source_keyword, ''), ''),
    CASE
      WHEN source_keyword ILIKE '%REWIRE%' THEN 'video'
      WHEN source_keyword ILIKE '%SHIFT%' THEN 'story'
      ELSE 'other'
    END,
    now(),
    'new',
    'warm',
    subscriber_id,
    tag_array,
    COALESCE(NULLIF(email, ''), ''),
    'webhook'
  )
  RETURNING id INTO new_lead_id;

  RETURN jsonb_build_object('status', 'ok', 'action', 'created', 'lead_id', new_lead_id);
END;
$$;

-- Allow unauthenticated (anon) calls for ManyChat webhooks
GRANT EXECUTE ON FUNCTION receive_manychat_lead TO anon;

-- ── STEP 4: Enable Realtime for live updates ──
ALTER PUBLICATION supabase_realtime ADD TABLE pipeline_leads;

-- ── STEP 5: Migrate existing leads from JSON blob ──
-- This moves any leads stored in wtd_store into the new table.
DO $$
DECLARE
  blob_value TEXT;
  leads JSONB;
  lead JSONB;
  admin_id UUID;
BEGIN
  SELECT id INTO admin_id FROM auth.users WHERE email = 'scott@scottzwills.com' LIMIT 1;
  IF admin_id IS NULL THEN RAISE NOTICE 'Admin not found — skipping migration'; RETURN; END IF;

  SELECT value INTO blob_value FROM wtd_store WHERE key = admin_id || ':pipeline-leads';
  IF blob_value IS NULL THEN RAISE NOTICE 'No existing pipeline leads — skipping migration'; RETURN; END IF;

  leads := blob_value::jsonb;

  FOR lead IN SELECT * FROM jsonb_array_elements(leads)
  LOOP
    INSERT INTO pipeline_leads (
      id, owner_id, name, ig_handle, source_keyword, source_type,
      lead_source, dm_date, first_reply_at, status, lead_quality,
      setter, setter_notes, objections, objection_categories,
      outcome_notes, booked_date, touchpoints, followups,
      mc_subscriber_id, mc_tags, mc_email, mc_source, created_at, updated_at
    ) VALUES (
      COALESCE((lead->>'id')::UUID, gen_random_uuid()),
      admin_id,
      COALESCE(lead->>'name', 'Unknown'),
      COALESCE(lead->>'ig_handle', ''),
      COALESCE(lead->>'source_keyword', ''),
      COALESCE(lead->>'source_type', 'other'),
      COALESCE(lead->>'lead_source', ''),
      COALESCE(NULLIF(lead->>'dm_date', '')::DATE, CURRENT_DATE)::TIMESTAMPTZ,
      NULLIF(lead->>'first_reply_at', '')::TIMESTAMPTZ,
      COALESCE(lead->>'status', 'new'),
      COALESCE(lead->>'lead_quality', 'warm'),
      COALESCE(lead->>'setter', ''),
      COALESCE(lead->>'setter_notes', ''),
      COALESCE(lead->>'objections', ''),
      COALESCE(
        (SELECT array_agg(el::TEXT) FROM jsonb_array_elements_text(COALESCE(lead->'objection_categories', '[]'::jsonb)) el),
        '{}'
      ),
      COALESCE(lead->>'outcome_notes', ''),
      NULLIF(lead->>'booked_date', '')::TIMESTAMPTZ,
      COALESCE((lead->>'touchpoints')::INTEGER, 0),
      COALESCE(lead->'followups', '[]'::jsonb),
      COALESCE(lead->>'mc_subscriber_id', ''),
      COALESCE(
        (SELECT array_agg(el::TEXT) FROM jsonb_array_elements_text(COALESCE(lead->'mc_tags', '[]'::jsonb)) el),
        '{}'
      ),
      COALESCE(lead->>'mc_email', ''),
      'manual',
      COALESCE(NULLIF(lead->>'created_at', '')::TIMESTAMPTZ, now()),
      COALESCE(NULLIF(lead->>'updated_at', '')::TIMESTAMPTZ, now())
    )
    ON CONFLICT (id) DO NOTHING;
  END LOOP;

  RAISE NOTICE 'Migration complete — leads moved to pipeline_leads table';
END $$;

-- ============================================================
-- DONE! After running this:
-- 1. Go to Database > Replication in Supabase Dashboard
-- 2. Make sure "pipeline_leads" shows as enabled
-- 3. Set up ManyChat webhook (see MANYCHAT-SETUP.md)
-- ============================================================
