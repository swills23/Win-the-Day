-- ============================================================
-- Win the Day — Instagram Content Intelligence Tables
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor
-- These tables store Instagram media, insights, and AI-generated scripts
-- ============================================================

-- ── 1. MEDIA ──
-- One row per Instagram post/reel/carousel/story
CREATE TABLE IF NOT EXISTS ig_media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id),
  ig_media_id TEXT NOT NULL,
  media_type TEXT DEFAULT '',
  media_url TEXT DEFAULT '',
  thumbnail_url TEXT DEFAULT '',
  permalink TEXT DEFAULT '',
  caption TEXT DEFAULT '',
  timestamp TIMESTAMPTZ,
  hook_text TEXT DEFAULT '',
  content_format TEXT DEFAULT '',
  topics TEXT[] DEFAULT '{}',
  frameworks_used TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(owner_id, ig_media_id)
);

CREATE INDEX IF NOT EXISTS idx_ig_media_owner ON ig_media(owner_id);
CREATE INDEX IF NOT EXISTS idx_ig_media_ts ON ig_media(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_ig_media_format ON ig_media(content_format);

-- ── 2. INSIGHTS ──
-- Metrics snapshot per media item per sync (time series)
CREATE TABLE IF NOT EXISTS ig_insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id),
  ig_media_id TEXT NOT NULL,
  synced_at TIMESTAMPTZ DEFAULT now(),
  views INTEGER DEFAULT 0,
  reach INTEGER DEFAULT 0,
  likes INTEGER DEFAULT 0,
  comments INTEGER DEFAULT 0,
  saves INTEGER DEFAULT 0,
  shares INTEGER DEFAULT 0,
  avg_watch_time NUMERIC(8,2) DEFAULT 0,
  engagement_rate NUMERIC(6,4) DEFAULT 0,
  save_rate NUMERIC(6,4) DEFAULT 0,
  share_rate NUMERIC(6,4) DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_ig_insights_owner ON ig_insights(owner_id);
CREATE INDEX IF NOT EXISTS idx_ig_insights_media ON ig_insights(ig_media_id);
CREATE INDEX IF NOT EXISTS idx_ig_insights_synced ON ig_insights(synced_at DESC);

-- ── 3. SCRIPTS ──
-- AI-generated video/content scripts
CREATE TABLE IF NOT EXISTS ig_scripts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id),
  title TEXT DEFAULT '',
  hook TEXT DEFAULT '',
  body TEXT DEFAULT '',
  format TEXT DEFAULT 'drawing_video',
  topic TEXT DEFAULT '',
  framework TEXT DEFAULT '',
  inspired_by TEXT[] DEFAULT '{}',
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft','approved','filmed','posted')),
  ai_reasoning TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ig_scripts_owner ON ig_scripts(owner_id);
CREATE INDEX IF NOT EXISTS idx_ig_scripts_status ON ig_scripts(status);

-- ── ROW LEVEL SECURITY ──

ALTER TABLE ig_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin manages ig_media" ON ig_media
  FOR ALL USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

ALTER TABLE ig_insights ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin manages ig_insights" ON ig_insights
  FOR ALL USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

ALTER TABLE ig_scripts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin manages ig_scripts" ON ig_scripts
  FOR ALL USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

-- ============================================================
-- DONE! Tables: ig_media, ig_insights, ig_scripts
-- ============================================================
