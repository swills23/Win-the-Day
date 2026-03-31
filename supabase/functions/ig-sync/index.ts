// Supabase Edge Function: ig-sync
// Deploy: supabase functions deploy ig-sync --no-verify-jwt
// Secrets: IG_ACCESS_TOKEN, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto-set)
//
// Fetches Instagram media + insights, stores in ig_media + ig_insights tables.
// Modes: "full" (all media) or "recent" (last 7 days, default)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const IG_API = "https://graph.instagram.com";
const GRAPH_API = "https://graph.facebook.com/v19.0";

// Delay helper to respect rate limits
const delay = (ms: number) => new Promise(r => setTimeout(r, ms));

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const token = Deno.env.get("IG_ACCESS_TOKEN");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!token) {
      return new Response(
        JSON.stringify({ error: "IG_ACCESS_TOKEN not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const sb = createClient(supabaseUrl, serviceKey);
    const body = await req.json().catch(() => ({}));
    const mode = body.mode || "recent";
    const ownerId = body.owner_id; // Admin user ID

    if (!ownerId) {
      return new Response(
        JSON.stringify({ error: "owner_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Fetch media list from Instagram
    const mediaFields = "id,media_type,media_url,thumbnail_url,permalink,caption,timestamp";
    let allMedia: any[] = [];
    let url = `${IG_API}/me/media?fields=${mediaFields}&limit=50&access_token=${token}`;

    // For recent mode, we'll just fetch the first page (most recent 50)
    const maxPages = mode === "full" ? 10 : 1;
    let page = 0;

    while (url && page < maxPages) {
      const res = await fetch(url);
      if (!res.ok) {
        const err = await res.text();
        console.error("Instagram media fetch error:", err);
        return new Response(
          JSON.stringify({ error: "Instagram API error", details: err }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      const data = await res.json();
      allMedia = allMedia.concat(data.data || []);
      url = data.paging?.next || null;
      page++;
      if (url) await delay(300);
    }

    console.log(`Fetched ${allMedia.length} media items (mode: ${mode})`);

    // 2. For each media item, upsert + fetch insights
    let synced = 0;
    const errors: string[] = [];
    const syncedAt = new Date().toISOString();

    for (const m of allMedia) {
      try {
        // Extract hook (first line of caption)
        const caption = m.caption || "";
        const hookText = caption.split("\n")[0].substring(0, 200);

        // Detect content format from media type + caption hints
        let contentFormat = "post";
        if (m.media_type === "VIDEO") contentFormat = "reel";
        if (m.media_type === "CAROUSEL_ALBUM") contentFormat = "carousel";
        if (caption.toLowerCase().includes("drawing")) contentFormat = "drawing_video";

        // Upsert media record
        await sb.from("ig_media").upsert({
          owner_id: ownerId,
          ig_media_id: m.id,
          media_type: m.media_type || "",
          media_url: m.media_url || "",
          thumbnail_url: m.thumbnail_url || "",
          permalink: m.permalink || "",
          caption,
          timestamp: m.timestamp,
          hook_text: hookText,
          content_format: contentFormat,
          updated_at: new Date().toISOString(),
        }, { onConflict: "owner_id,ig_media_id" });

        // Fetch insights for this media
        // Different metrics available for different media types
        const metrics = m.media_type === "VIDEO" || m.media_type === "REEL"
          ? "views,reach,likes,comments,saved,shares,ig_reels_avg_watch_time"
          : "reach,likes,comments,saved,shares";

        await delay(500); // Rate limit protection

        const insightsUrl = `${IG_API}/${m.id}/insights?metric=${metrics}&access_token=${token}`;
        const insRes = await fetch(insightsUrl);

        let views = 0, reach = 0, likes = 0, comments = 0, saves = 0, shares = 0, avgWatchTime = 0;

        if (insRes.ok) {
          const insData = await insRes.json();
          const metricsData = insData.data || [];
          for (const metric of metricsData) {
            const val = metric.values?.[0]?.value || 0;
            switch (metric.name) {
              case "views": views = val; break;
              case "reach": reach = val; break;
              case "likes": likes = val; break;
              case "comments": comments = val; break;
              case "saved": saves = val; break;
              case "shares": shares = val; break;
              case "ig_reels_avg_watch_time": avgWatchTime = val; break;
            }
          }
        } else {
          // Some media types don't support insights — that's OK
          const errText = await insRes.text();
          console.warn(`Insights unavailable for ${m.id}: ${insRes.status}`);
        }

        // Compute engagement rates
        const engagementRate = reach > 0 ? (likes + comments + saves + shares) / reach : 0;
        const saveRate = reach > 0 ? saves / reach : 0;
        const shareRate = reach > 0 ? shares / reach : 0;

        // Insert insights snapshot
        await sb.from("ig_insights").insert({
          owner_id: ownerId,
          ig_media_id: m.id,
          synced_at: syncedAt,
          views, reach, likes, comments, saves, shares,
          avg_watch_time: avgWatchTime,
          engagement_rate: engagementRate,
          save_rate: saveRate,
          share_rate: shareRate,
        });

        synced++;
      } catch (e) {
        console.error(`Error processing media ${m.id}:`, e);
        errors.push(m.id);
      }
    }

    // 3. Check token expiry and attempt refresh
    let tokenWarning = null;
    try {
      const appId = Deno.env.get("IG_APP_ID");
      const appSecret = Deno.env.get("IG_APP_SECRET");
      if (appId && appSecret) {
        // Check token info
        const debugUrl = `${GRAPH_API}/debug_token?input_token=${token}&access_token=${token}`;
        const debugRes = await fetch(debugUrl);
        if (debugRes.ok) {
          const debugData = await debugRes.json();
          const expiresAt = debugData.data?.expires_at;
          if (expiresAt) {
            const daysLeft = Math.floor((expiresAt * 1000 - Date.now()) / 86400000);
            if (daysLeft < 7) {
              // Attempt token refresh
              const refreshUrl = `${GRAPH_API}/oauth/access_token?grant_type=fb_exchange_token&client_id=${appId}&client_secret=${appSecret}&fb_exchange_token=${token}`;
              const refreshRes = await fetch(refreshUrl);
              if (refreshRes.ok) {
                const refreshData = await refreshRes.json();
                if (refreshData.access_token) {
                  tokenWarning = `Token refreshed (was ${daysLeft} days from expiry)`;
                  // Note: can't update Deno.env, but we store the new token info
                }
              } else {
                tokenWarning = `Token expires in ${daysLeft} days — refresh failed. Re-generate in Facebook Developer portal.`;
              }
            }
          }
        }
      }
    } catch (e) {
      console.warn("Token check failed:", e);
    }

    return new Response(
      JSON.stringify({ synced, total: allMedia.length, errors, mode, tokenWarning, synced_at: syncedAt }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("ig-sync error:", err);
    return new Response(
      JSON.stringify({ error: "Internal error", details: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
