// Supabase Edge Function: ig-analyze
// Deploy: supabase functions deploy ig-analyze --no-verify-jwt
// Secrets: ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto-set)
//
// Two modes:
//   { action: "analyze", owner_id } — AI content performance analysis
//   { action: "generate", owner_id, topic?, format?, count? } — AI script generation

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_ORIGINS = [
  "https://app.scottzwills.com",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
];

function getCorsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

// Rate limit: 5 requests per 10 minutes per user
const rateLimitMap = new Map<string, { count: number; reset: number }>();
const RATE_LIMIT = 5;
const RATE_WINDOW = 10 * 60_000;

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(userId);
  if (!entry || now > entry.reset) {
    rateLimitMap.set(userId, { count: 1, reset: now + RATE_WINDOW });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

async function verifyAdmin(req: Request): Promise<{ userId: string } | null> {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error } = await sb.auth.getUser();
  if (error || !user) return null;

  // Verify admin status
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminSb = createClient(supabaseUrl, serviceKey);
  const { data: profile } = await adminSb
    .from("wtd_profiles")
    .select("is_admin")
    .eq("id", user.id)
    .single();

  if (!profile?.is_admin) return null;
  return { userId: user.id };
}

async function callClaude(system: string, userMessage: string, maxTokens = 4096) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userMessage }],
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Anthropic API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  return data.content?.[0]?.text || "";
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Auth + admin verification
    const auth = await verifyAdmin(req);
    if (!auth) {
      return new Response(
        JSON.stringify({ error: "Unauthorized — admin access required" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Rate limit
    if (!checkRateLimit(auth.userId)) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded. Try again in a few minutes." }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!ANTHROPIC_API_KEY) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(supabaseUrl, serviceKey);

    const body = await req.json();
    const { action } = body;
    // Use authenticated user's ID, not the request body
    const owner_id = auth.userId;

    // Load media + latest insights
    const { data: media } = await sb
      .from("ig_media")
      .select("*")
      .eq("owner_id", owner_id)
      .order("timestamp", { ascending: false })
      .limit(100);

    if (!media || !media.length) {
      return new Response(
        JSON.stringify({ error: "No media data. Run a sync first." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get latest insights for each media item
    const mediaIds = media.map(m => m.ig_media_id);
    const { data: insights } = await sb
      .from("ig_insights")
      .select("*")
      .eq("owner_id", owner_id)
      .in("ig_media_id", mediaIds)
      .order("synced_at", { ascending: false });

    // Deduplicate: keep only latest insight per media
    const latestInsights: Record<string, any> = {};
    for (const ins of (insights || [])) {
      if (!latestInsights[ins.ig_media_id]) {
        latestInsights[ins.ig_media_id] = ins;
      }
    }

    // Merge media + insights
    const posts = media.map(m => ({
      id: m.ig_media_id,
      type: m.media_type,
      format: m.content_format,
      caption: (m.caption || "").substring(0, 500),
      hook: m.hook_text,
      date: m.timestamp,
      permalink: m.permalink,
      ...(latestInsights[m.ig_media_id] || {}),
    }));

    // Sort by engagement rate
    posts.sort((a, b) => (b.engagement_rate || 0) - (a.engagement_rate || 0));

    if (action === "analyze") {
      // Also load pipeline leads for correlation
      const { data: leads } = await sb
        .from("pipeline_leads")
        .select("dm_date, source, source_keyword, content_format, status")
        .eq("owner_id", owner_id)
        .order("dm_date", { ascending: false })
        .limit(100);

      const system = `You are a content strategist analyzing Instagram performance data for a coaching brand.
The brand targets high-agency men stuck in self-sabotage cycles. Content types include drawing videos, carousels, reels, and stories.

Analyze the performance data and provide actionable insights. Focus on:
1. HOOK PATTERNS: What opening lines/first 3 seconds drive the highest engagement?
2. TOPIC PATTERNS: Which topics (identity, discipline myth, patterns, rewiring) perform best?
3. FORMAT PATTERNS: Which content formats drive saves and shares vs just views?
4. SAVE/SHARE ANALYSIS: Saves = intent, shares = virality. What triggers each?
5. CONTENT-TO-LEAD CORRELATION: If pipeline data is provided, which content types correlate with DMs and bookings?

Do NOT report vanity metrics. Focus on what's actionable — what to make more of, what to stop, and why.

Respond ONLY with valid JSON in this structure:
{
  "top_patterns": [{ "pattern": "...", "evidence": "...", "recommendation": "..." }],
  "format_ranking": [{ "format": "...", "strength": "...", "weakness": "..." }],
  "hook_analysis": { "winning_hooks": ["..."], "losing_hooks": ["..."], "formula": "..." },
  "content_to_leads": { "insight": "...", "best_format_for_dms": "..." },
  "action_items": ["...", "...", "..."]
}`;

      const userMsg = `Here are the last ${posts.length} Instagram posts ranked by engagement rate:\n\n${JSON.stringify(posts.slice(0, 30), null, 2)}\n\n${leads?.length ? `Pipeline leads (${leads.length} total):\n${JSON.stringify(leads.slice(0, 30), null, 2)}` : "No pipeline lead data available."}`;

      const reply = await callClaude(system, userMsg, 3000);

      // Try to parse as JSON, fallback to raw text
      let analysis;
      try {
        analysis = JSON.parse(reply);
      } catch {
        // Try to extract JSON from markdown code blocks
        const jsonMatch = reply.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (jsonMatch) {
          try { analysis = JSON.parse(jsonMatch[1]); } catch { analysis = { raw: reply }; }
        } else {
          analysis = { raw: reply };
        }
      }

      return new Response(
        JSON.stringify({ analysis }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );

    } else if (action === "generate") {
      const topic = body.topic || "";
      const format = body.format || "drawing_video";
      const count = Math.min(body.count || 3, 5);

      // Get recent scripts to avoid repeats
      const { data: recentScripts } = await sb
        .from("ig_scripts")
        .select("title, hook, topic")
        .eq("owner_id", owner_id)
        .order("created_at", { ascending: false })
        .limit(10);

      const system = `You write Instagram drawing video scripts for Scott Wills' coaching brand.

VOICE RULES:
- Direct, no fluff
- Uses analogies heavily (beach ball underwater, thermostat, mopping while faucet runs)
- Speaks from lived experience — reference "The Loop" (23 restarts over 5.5 years)
- Anti-discipline positioning: discipline is a bandaid, change happens at identity level
- Never use: "hustle," "grind," "just be consistent," or generic motivation language
- Phrases Scott uses: "something underneath was running the show," "the gap between knowing and doing," "rewire the pattern," "you're not lacking discipline — you're running a pattern you don't see"

SCRIPT STRUCTURE (drawing video):
1. HOOK (first line — stop the scroll): Pattern interrupt, contrarian take, or vulnerable "I" statement
2. SETUP (10-15 sec): Establish the problem the viewer recognizes in themselves
3. TENSION (15-20 sec): Why the obvious solution (discipline, habits, willpower) doesn't work
4. SHIFT (10-15 sec): The identity-level insight or reframe
5. CLOSE (5-10 sec): Resonant ending line or soft CTA

Respond ONLY with valid JSON:
{
  "scripts": [{
    "title": "short title",
    "hook": "the opening line",
    "body": "HOOK: ...\\nSETUP: ...\\nTENSION: ...\\nSHIFT: ...\\nCLOSE: ...",
    "format": "${format}",
    "topic": "main topic",
    "framework": "which Scott framework it uses (The Loop, Predictive Models, Rewiring, The Gap, etc)",
    "reasoning": "Why this should perform well based on the data"
  }]
}`;

      const topPosts = posts.slice(0, 10);
      const bottomPosts = posts.slice(-5);

      const userMsg = `Generate ${count} new ${format} scripts${topic ? ` about "${topic}"` : ""}.

TOP PERFORMING POSTS (learn from these):
${JSON.stringify(topPosts, null, 2)}

UNDERPERFORMING POSTS (avoid these patterns):
${JSON.stringify(bottomPosts, null, 2)}

${recentScripts?.length ? `RECENTLY GENERATED (don't repeat these):\n${JSON.stringify(recentScripts, null, 2)}` : ""}`;

      const reply = await callClaude(system, userMsg, 4096);

      let scripts;
      try {
        scripts = JSON.parse(reply);
      } catch {
        const jsonMatch = reply.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (jsonMatch) {
          try { scripts = JSON.parse(jsonMatch[1]); } catch { scripts = { raw: reply }; }
        } else {
          scripts = { raw: reply };
        }
      }

      // Save generated scripts to database
      if (scripts.scripts && Array.isArray(scripts.scripts)) {
        for (const s of scripts.scripts) {
          await sb.from("ig_scripts").insert({
            owner_id,
            title: s.title || "",
            hook: s.hook || "",
            body: s.body || "",
            format: s.format || format,
            topic: s.topic || topic,
            framework: s.framework || "",
            inspired_by: topPosts.slice(0, 3).map(p => p.id),
            ai_reasoning: s.reasoning || "",
            status: "draft",
          });
        }
      }

      return new Response(
        JSON.stringify(scripts),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Invalid action. Use 'analyze' or 'generate'." }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("ig-analyze error:", err);
    return new Response(
      JSON.stringify({ error: "Internal error", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
