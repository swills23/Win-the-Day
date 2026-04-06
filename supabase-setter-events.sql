-- ============================================================
-- Win the Day — Setter Events Table + Webhook
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor
--
-- This creates the event log for tracking setter activity
-- from ManyChat webhooks: new DMs, setter replies, bookings.
-- ============================================================

-- ── STEP 1: Create setter_events table ──
CREATE TABLE IF NOT EXISTS setter_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('new_dm', 'setter_reply', 'booked', 'qualified', 'tag_change')),
  subscriber_id TEXT NOT NULL,
  subscriber_name TEXT DEFAULT '',
  ig_handle TEXT DEFAULT '',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_se_type_date ON setter_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_se_subscriber ON setter_events(subscriber_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_se_owner ON setter_events(owner_id);
CREATE INDEX IF NOT EXISTS idx_se_date ON setter_events(created_at DESC);

-- ── STEP 2: Row Level Security ──
ALTER TABLE setter_events ENABLE ROW LEVEL SECURITY;

-- Admin can read all events
CREATE POLICY "Admin reads setter events" ON setter_events
  FOR SELECT USING (auth.jwt() ->> 'email' = 'scott@scottzwills.com');

-- Admin can insert events (for manual logging)
CREATE POLICY "Admin inserts setter events" ON setter_events
  FOR INSERT WITH CHECK (auth.jwt() ->> 'email' = 'scott@scottzwills.com');

-- ── STEP 3: Webhook function for ManyChat events ──
CREATE OR REPLACE FUNCTION receive_setter_event(
  webhook_secret TEXT,
  event_type TEXT,
  subscriber_id TEXT,
  subscriber_name TEXT DEFAULT '',
  ig_username TEXT DEFAULT '',
  email TEXT DEFAULT '',
  tags TEXT DEFAULT '',
  country TEXT DEFAULT '',
  custom_data JSONB DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  stored_secret TEXT;
  owner UUID;
  meta JSONB;
  lead_id UUID;
BEGIN
  -- Validate webhook secret
  stored_secret := current_setting('app.manychat_webhook_secret', true);
  IF stored_secret IS NULL OR stored_secret = '' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Webhook secret not configured');
  END IF;
  IF webhook_secret IS NULL OR webhook_secret != stored_secret THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Invalid webhook secret');
  END IF;

  -- Validate required fields
  IF event_type IS NULL OR event_type NOT IN ('new_dm', 'setter_reply', 'booked', 'qualified', 'tag_change') THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Invalid event_type');
  END IF;
  IF subscriber_id IS NULL OR subscriber_id = '' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'subscriber_id required');
  END IF;

  -- Get owner (Scott's user ID — the admin)
  SELECT id INTO owner FROM auth.users WHERE email = 'scott@scottzwills.com' LIMIT 1;

  -- Build metadata
  meta := jsonb_build_object(
    'email', COALESCE(email, ''),
    'tags', COALESCE(tags, ''),
    'country', COALESCE(country, '')
  ) || COALESCE(custom_data, '{}');

  -- Insert event
  INSERT INTO setter_events (owner_id, event_type, subscriber_id, subscriber_name, ig_handle, metadata)
  VALUES (owner, event_type, subscriber_id, COALESCE(subscriber_name, ''), COALESCE(ig_username, ''), meta);

  -- On new_dm: auto-create pipeline lead if doesn't exist
  IF event_type = 'new_dm' THEN
    SELECT id INTO lead_id FROM pipeline_leads
      WHERE owner_id = owner AND mc_subscriber_id = subscriber_id LIMIT 1;

    IF lead_id IS NULL THEN
      INSERT INTO pipeline_leads (
        owner_id, name, ig_handle, mc_subscriber_id, mc_email,
        mc_tags, mc_source, status, lead_quality, dm_date, stage_entered_at,
        country
      ) VALUES (
        owner,
        COALESCE(subscriber_name, ''),
        COALESCE(ig_username, ''),
        subscriber_id,
        COALESCE(email, ''),
        CASE WHEN tags IS NOT NULL AND tags != '' THEN string_to_array(tags, ',') ELSE '{}' END,
        'webhook',
        'new',
        'warm',
        now(),
        now(),
        COALESCE(NULLIF(country, ''), NULL)
      )
      ON CONFLICT (owner_id, mc_subscriber_id) DO UPDATE SET
        mc_tags = CASE WHEN tags IS NOT NULL AND tags != '' THEN string_to_array(tags, ',') ELSE pipeline_leads.mc_tags END,
        mc_email = CASE WHEN email IS NOT NULL AND email != '' THEN email ELSE pipeline_leads.mc_email END,
        ig_handle = CASE WHEN ig_username IS NOT NULL AND ig_username != '' THEN ig_username ELSE pipeline_leads.ig_handle END,
        updated_at = now();
    END IF;
  END IF;

  -- On booked: update lead status
  IF event_type = 'booked' THEN
    UPDATE pipeline_leads
      SET status = 'booked', booked_date = now(), stage_entered_at = now(), updated_at = now()
      WHERE owner_id = owner AND mc_subscriber_id = subscriber_id AND status NOT IN ('booked', 'completed_call', 'closed_won');
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'event_type', event_type, 'subscriber_id', subscriber_id);
END;
$$;

-- Grant anon access to webhook (ManyChat calls without auth)
GRANT EXECUTE ON FUNCTION receive_setter_event TO anon;

-- ── STEP 4: Add unique constraint for lead dedup ──
-- (safe to run if constraint already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'pipeline_leads_owner_mc_sub_unique'
  ) THEN
    ALTER TABLE pipeline_leads ADD CONSTRAINT pipeline_leads_owner_mc_sub_unique
      UNIQUE (owner_id, mc_subscriber_id);
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL; -- Ignore if already exists or column missing
END $$;

-- ============================================================
-- DONE! Now set up 3 ManyChat flows:
-- 1. Trigger: "Conversation opened" → External Request → event_type: "new_dm"
-- 2. Trigger: "Agent sends message" → External Request → event_type: "setter_reply"
-- 3. Trigger: Tag "booked" applied → External Request → event_type: "booked"
--
-- Webhook URL: https://ceahoxydtjcprjkbjakn.supabase.co/rest/v1/rpc/receive_setter_event
-- Headers: Content-Type: application/json, apikey: YOUR_ANON_KEY
-- Body: {"webhook_secret":"YOUR_SECRET","event_type":"new_dm","subscriber_id":"{{id}}","subscriber_name":"{{first_name}} {{last_name}}","ig_username":"{{ig_username}}","email":"{{email}}","tags":"{{tags}}"}
-- ============================================================
