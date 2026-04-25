// Supabase Edge Function: confirm-user
// Called immediately after signup to auto-confirm email + create profile
// Deploy: supabase functions deploy confirm-user --no-verify-jwt

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_ORIGINS = ["https://app.scottzwills.com", "https://win-the-day-five.vercel.app"];

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  if (!ALLOWED_ORIGINS.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req);
  if (!corsHeaders) return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 });

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, email } = await req.json();

    if (!user_id || !email) {
      return new Response(
        JSON.stringify({ error: "user_id and email required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(supabaseUrl, serviceKey);

    // Auto-confirm email
    const { error: confirmError } = await sb.auth.admin.updateUserById(user_id, {
      email_confirm: true,
    });

    if (confirmError) {
      console.error("Confirm error:", confirmError);
    }

    // Create profile (pending approval)
    const { error: profileError } = await sb.from("wtd_profiles").upsert(
      { id: user_id, email, approved: false, is_admin: false },
      { onConflict: "id" }
    );

    if (profileError) {
      console.error("Profile error:", profileError);
    }

    return new Response(
      JSON.stringify({ status: "ok", confirmed: !confirmError, profile: !profileError }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("confirm-user error:", err);
    return new Response(
      JSON.stringify({ error: "Internal error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
