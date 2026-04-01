-- ============================================================
-- Win the Day — AI Check-ins Table
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS wtd_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  email TEXT,
  messages JSONB DEFAULT '[]',
  context TEXT DEFAULT '',
  mood_before INTEGER DEFAULT 0,
  mood_after INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_checkins_user ON wtd_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_checkins_date ON wtd_checkins(created_at DESC);

-- RLS
ALTER TABLE wtd_checkins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own checkins" ON wtd_checkins
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own checkins" ON wtd_checkins
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users update own checkins" ON wtd_checkins
  FOR UPDATE USING (auth.uid() = user_id);

-- Admin (Scott) can read all checkins
CREATE POLICY "Admin reads all checkins" ON wtd_checkins
  FOR SELECT USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

-- Also create the feedback table if not exists
CREATE TABLE IF NOT EXISTS wtd_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  email TEXT,
  type TEXT CHECK (type IN ('suggestion', 'bug')),
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE wtd_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own feedback" ON wtd_feedback
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admin reads all feedback" ON wtd_feedback
  FOR SELECT USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

-- ============================================================
-- DONE! Tables created for:
--   - wtd_checkins: AI check-in conversations
--   - wtd_feedback: Bug reports and suggestions
-- ============================================================
