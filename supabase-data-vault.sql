-- ============================================================
-- Win the Day — Data Vault Tables
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor
-- These tables create a structured, queryable data vault
-- for coaching analytics across all clients.
-- ============================================================

-- ── 1. DAILY LOGS ──
-- One row per user per day. The core record of how each day went.
CREATE TABLE IF NOT EXISTS wtd_daily_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  date DATE NOT NULL,
  score NUMERIC(5,4) DEFAULT 0,          -- 0.0000 to 1.0000
  earned INTEGER DEFAULT 0,
  total INTEGER DEFAULT 0,
  tasks_done INTEGER DEFAULT 0,
  tasks_total INTEGER DEFAULT 0,
  mood INTEGER DEFAULT 0,                 -- 1-5
  streak INTEGER DEFAULT 0,
  rest_day BOOLEAN DEFAULT false,
  reflection TEXT DEFAULT '',
  win_of_day TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_daily_user ON wtd_daily_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_date ON wtd_daily_logs(date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_user_date ON wtd_daily_logs(user_id, date DESC);

-- ── 2. TASK LOGS ──
-- One row per task per user per day. Shows exactly what was done/missed.
CREATE TABLE IF NOT EXISTS wtd_task_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  date DATE NOT NULL,
  task_id INTEGER NOT NULL,
  task_name TEXT NOT NULL,
  tier TEXT DEFAULT 'B' CHECK (tier IN ('S','A','B')),
  block TEXT DEFAULT '',
  points INTEGER DEFAULT 1,
  completed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, date, task_id)
);

CREATE INDEX IF NOT EXISTS idx_task_user ON wtd_task_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_task_date ON wtd_task_logs(date DESC);
CREATE INDEX IF NOT EXISTS idx_task_user_date ON wtd_task_logs(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_task_name ON wtd_task_logs(task_name);
CREATE INDEX IF NOT EXISTS idx_task_completed ON wtd_task_logs(completed);

-- ── 3. GOAL LOGS ──
-- Tracks goal creation, updates, and completion over time.
CREATE TABLE IF NOT EXISTS wtd_goal_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  goal_type TEXT NOT NULL CHECK (goal_type IN ('weekly','monthly','yearly')),
  goal_text TEXT NOT NULL,
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low','medium','high')),
  completed BOOLEAN DEFAULT false,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_goal_user ON wtd_goal_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_goal_type ON wtd_goal_logs(goal_type);
CREATE INDEX IF NOT EXISTS idx_goal_completed ON wtd_goal_logs(completed);

-- ── 4. IDENTITY LOGS ──
-- Tracks identity reflections and ratings over time.
CREATE TABLE IF NOT EXISTS wtd_identity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  date DATE NOT NULL,
  identity_statement TEXT DEFAULT '',
  why_statement TEXT DEFAULT '',
  rating INTEGER DEFAULT 0,              -- 1-5 identity alignment rating
  note TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_identity_user ON wtd_identity_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_identity_date ON wtd_identity_logs(date DESC);

-- ── 5. REPORT PREFERENCES ──
-- Stores each client's email report preferences.
CREATE TABLE IF NOT EXISTS wtd_report_prefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  weekly_email BOOLEAN DEFAULT false,
  monthly_email BOOLEAN DEFAULT false,
  email TEXT DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_report_prefs_user ON wtd_report_prefs(user_id);

-- ── ROW LEVEL SECURITY ──

-- Daily logs
ALTER TABLE wtd_daily_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own daily logs" ON wtd_daily_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own daily logs" ON wtd_daily_logs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users read own daily logs" ON wtd_daily_logs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admin reads all daily logs" ON wtd_daily_logs
  FOR SELECT USING (
    auth.uid() IN (SELECT id FROM auth.users WHERE email = 'scott@scottzwills.com')
  );

-- Task logs
ALTER TABLE wtd_task_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own task logs" ON wtd_task_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own task logs" ON wtd_task_logs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users read own task logs" ON wtd_task_logs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admin reads all task logs" ON wtd_task_logs
  FOR SELECT USING (
    auth.uid() IN (SELECT id FROM auth.users WHERE email = 'scott@scottzwills.com')
  );

-- Goal logs
ALTER TABLE wtd_goal_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own goal logs" ON wtd_goal_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own goal logs" ON wtd_goal_logs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users read own goal logs" ON wtd_goal_logs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admin reads all goal logs" ON wtd_goal_logs
  FOR SELECT USING (
    auth.uid() IN (SELECT id FROM auth.users WHERE email = 'scott@scottzwills.com')
  );

-- Identity logs
ALTER TABLE wtd_identity_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users insert own identity logs" ON wtd_identity_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users update own identity logs" ON wtd_identity_logs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users read own identity logs" ON wtd_identity_logs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admin reads all identity logs" ON wtd_identity_logs
  FOR SELECT USING (
    auth.uid() IN (SELECT id FROM auth.users WHERE email = 'scott@scottzwills.com')
  );

-- Report prefs
ALTER TABLE wtd_report_prefs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own report prefs" ON wtd_report_prefs
  FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Admin reads all report prefs" ON wtd_report_prefs
  FOR SELECT USING (
    auth.uid() IN (SELECT id FROM auth.users WHERE email = 'scott@scottzwills.com')
  );

-- ============================================================
-- DONE! Tables created:
--   - wtd_daily_logs: Daily scores, mood, streaks, reflections
--   - wtd_task_logs: Every task completion/miss per user per day
--   - wtd_goal_logs: Goal tracking over time
--   - wtd_identity_logs: Identity reflections and ratings
--   - wtd_report_prefs: Client email report preferences
--
-- Next: Run this SQL in Supabase Dashboard > SQL Editor
-- ============================================================
