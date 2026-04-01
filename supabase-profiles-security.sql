-- ============================================================
-- Win the Day — wtd_profiles Security Hardening
-- ============================================================
-- CRITICAL: Run this in Supabase Dashboard > SQL Editor
--
-- This adds RLS to the wtd_profiles table to prevent users from
-- escalating privileges by setting is_admin = true.
-- ============================================================

-- Create the table if it doesn't exist yet
CREATE TABLE IF NOT EXISTS wtd_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id),
  email TEXT DEFAULT '',
  approved BOOLEAN DEFAULT false,
  is_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE wtd_profiles ENABLE ROW LEVEL SECURITY;

-- Drop any existing permissive policies first (safe if they don't exist)
DROP POLICY IF EXISTS "Users read own profile" ON wtd_profiles;
DROP POLICY IF EXISTS "Users insert own profile" ON wtd_profiles;
DROP POLICY IF EXISTS "Users update own profile" ON wtd_profiles;
DROP POLICY IF EXISTS "Admin reads all profiles" ON wtd_profiles;
DROP POLICY IF EXISTS "Admin manages all profiles" ON wtd_profiles;

-- Users can read their own profile
CREATE POLICY "Users read own profile" ON wtd_profiles
  FOR SELECT USING (auth.uid() = id);

-- Users can insert their own profile (signup flow)
-- CRITICAL: is_admin and approved are forced to false on insert via trigger
CREATE POLICY "Users insert own profile" ON wtd_profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Users can update their own profile BUT only non-sensitive fields
-- is_admin and approved CANNOT be changed by the user (enforced by trigger below)
CREATE POLICY "Users update own profile" ON wtd_profiles
  FOR UPDATE USING (auth.uid() = id);

-- Admin can read all profiles (use JWT email to avoid auth.users permission issue)
CREATE POLICY "Admin reads all profiles" ON wtd_profiles
  FOR SELECT USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

-- Admin can update all profiles (approve users, etc.)
CREATE POLICY "Admin manages all profiles" ON wtd_profiles
  FOR UPDATE USING (
    auth.jwt() ->> 'email' = 'scott@scottzwills.com'
  );

-- ── TRIGGER: Prevent privilege escalation ──
-- This trigger ensures non-admin users cannot set is_admin = true
-- or approved = true for themselves.
CREATE OR REPLACE FUNCTION protect_profile_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller_is_admin BOOLEAN;
BEGIN
  -- Check if the calling user is admin (use JWT to avoid auth.users permission issue)
  caller_is_admin := (auth.jwt() ->> 'email') = 'scott@scottzwills.com';

  IF NOT caller_is_admin THEN
    -- Non-admin users: force is_admin to false, preserve approved from existing row
    IF TG_OP = 'INSERT' THEN
      NEW.is_admin := false;
      NEW.approved := false;
    ELSIF TG_OP = 'UPDATE' THEN
      NEW.is_admin := OLD.is_admin;  -- Cannot change is_admin
      NEW.approved := OLD.approved;  -- Cannot change approved
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS protect_profile_trigger ON wtd_profiles;
CREATE TRIGGER protect_profile_trigger
  BEFORE INSERT OR UPDATE ON wtd_profiles
  FOR EACH ROW
  EXECUTE FUNCTION protect_profile_fields();

-- ============================================================
-- DONE! wtd_profiles is now protected:
--   - RLS enabled: users can only read/write their own profile
--   - Trigger: non-admin users CANNOT set is_admin or approved
--   - Admin (scott@scottzwills.com) has full control
--
-- IMPORTANT: Run this ASAP — without this, any authenticated
-- user can make themselves admin.
-- ============================================================
