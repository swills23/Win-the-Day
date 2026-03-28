-- ============================================================
-- ManyChat API Proxy — Supabase RPC Function
-- ============================================================
-- Run this in Supabase Dashboard > SQL Editor
--
-- FIRST: Enable the http extension:
--   Go to Database > Extensions > search "http" > Enable it
--
-- THEN run this SQL.
-- ============================================================

-- Enable http extension (safe to run even if already enabled)
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- Create proxy function
CREATE OR REPLACE FUNCTION proxy_manychat_api(
  api_key TEXT,
  api_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  response extensions.http_response;
  result JSONB;
BEGIN
  -- Validate inputs
  IF api_key IS NULL OR api_key = '' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Missing API key');
  END IF;

  IF api_path IS NULL OR api_path NOT LIKE '/fb/%' THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Invalid API path');
  END IF;

  -- Call ManyChat API via http extension
  SELECT * INTO response FROM extensions.http((
    'GET',
    'https://api.manychat.com' || api_path,
    ARRAY[
      extensions.http_header('Authorization', 'Bearer ' || api_key),
      extensions.http_header('Accept', 'application/json')
    ],
    NULL,
    NULL
  )::extensions.http_request);

  -- Parse response
  BEGIN
    result := response.content::jsonb;
  EXCEPTION WHEN OTHERS THEN
    result := jsonb_build_object('status', 'error', 'message', 'Failed to parse response');
  END;

  RETURN result;
END;
$$;

-- Allow authenticated users and anon (for flexibility)
GRANT EXECUTE ON FUNCTION proxy_manychat_api TO authenticated;
GRANT EXECUTE ON FUNCTION proxy_manychat_api TO anon;
