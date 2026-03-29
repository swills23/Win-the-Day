// Supabase Edge Function: send-report
// Deploy with: supabase functions deploy send-report
// Required env vars: RESEND_API_KEY, REPORT_FROM_EMAIL (optional, defaults to reports@scottzwills.com)
//
// This function generates an HTML email with weekly or monthly report data
// and sends it via the Resend API. Falls back to JSON response if Resend is not configured.
//
// Trigger: POST /functions/v1/send-report
// Body: { type: 'weekly' | 'monthly', data: ReportData }
//
// Can also be triggered on a cron schedule via Supabase pg_cron or external scheduler.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface WeeklyReportData {
  type: "weekly";
  label: string;
  won: number;
  total: number;
  avg: number;
  streak: number;
  skipped: { name: string; tier: string; missRate: number }[];
  email: string;
}

interface MonthlyReportData {
  type: "monthly";
  label: string;
  won: number;
  tracked: number;
  total: number;
  avg: number;
  streak: number;
  bestStreak: number;
  consistency: number;
  email: string;
}

type ReportData = WeeklyReportData | MonthlyReportData;

function generateWeeklyEmailHTML(data: WeeklyReportData): string {
  const winRate = data.total > 0 ? Math.round((data.won / data.total) * 100) : 0;
  const skippedRows = data.skipped
    .map(
      (s) =>
        `<tr><td style="padding:8px 12px;font-size:14px;color:#1d1d1f;border-bottom:1px solid #e5e5ea">${s.name} <span style="font-size:11px;color:${s.tier === "S" ? "#C8891A" : s.tier === "A" ? "#3A7EC4" : "#888"}">${s.tier}</span></td><td style="padding:8px 12px;font-size:14px;color:#EF4444;text-align:right;border-bottom:1px solid #e5e5ea">${s.missRate}% missed</td></tr>`
    )
    .join("");

  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:24px">
    <h1 style="font-size:20px;color:#1d1d1f;margin:0 0 4px">Win the Day</h1>
    <p style="font-size:13px;color:#8e8e93;margin:0">Weekly Report - ${data.label}</p>
  </div>
  <div style="background:#fff;border-radius:12px;padding:20px;margin-bottom:16px;border:1px solid #e5e5ea">
    <div style="display:flex;text-align:center">
      <div style="flex:1;padding:12px">
        <div style="font-size:28px;font-weight:600;color:${winRate >= 70 ? "#22C55E" : winRate >= 40 ? "#F59E0B" : "#EF4444"}">${data.won}/${data.total}</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Days Won</div>
      </div>
      <div style="flex:1;padding:12px;border-left:1px solid #e5e5ea;border-right:1px solid #e5e5ea">
        <div style="font-size:28px;font-weight:600;color:#4F7BE8">${data.avg}%</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Avg Score</div>
      </div>
      <div style="flex:1;padding:12px">
        <div style="font-size:28px;font-weight:600;color:#F59E0B">${data.streak}</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Streak</div>
      </div>
    </div>
  </div>
  ${
    data.skipped.length
      ? `<div style="background:#fff;border-radius:12px;padding:16px;margin-bottom:16px;border:1px solid #e5e5ea">
    <div style="font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:#8e8e93;margin-bottom:10px;font-weight:500">Most Skipped Tasks</div>
    <table style="width:100%;border-collapse:collapse">${skippedRows}</table>
  </div>`
      : ""
  }
  <div style="text-align:center;padding:16px 0">
    <a href="https://app.scottzwills.com" style="display:inline-block;padding:12px 28px;background:#1d1d1f;color:#fff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:500">Open Win the Day</a>
  </div>
  <p style="text-align:center;font-size:11px;color:#8e8e93;margin-top:20px">You're receiving this because you enabled weekly reports in Win the Day.</p>
</div>
</body>
</html>`;
}

function generateMonthlyEmailHTML(data: MonthlyReportData): string {
  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:24px">
    <h1 style="font-size:20px;color:#1d1d1f;margin:0 0 4px">Win the Day</h1>
    <p style="font-size:13px;color:#8e8e93;margin:0">Monthly Report - ${data.label}</p>
  </div>
  <div style="background:#fff;border-radius:12px;padding:20px;margin-bottom:16px;border:1px solid #e5e5ea">
    <div style="display:flex;text-align:center;flex-wrap:wrap">
      <div style="flex:1;min-width:100px;padding:12px">
        <div style="font-size:28px;font-weight:600;color:#22C55E">${data.won}</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Days Won</div>
      </div>
      <div style="flex:1;min-width:100px;padding:12px">
        <div style="font-size:28px;font-weight:600;color:#4F7BE8">${data.avg}%</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Avg Score</div>
      </div>
      <div style="flex:1;min-width:100px;padding:12px">
        <div style="font-size:28px;font-weight:600;color:#F59E0B">${data.consistency}%</div>
        <div style="font-size:11px;color:#8e8e93;text-transform:uppercase;letter-spacing:.06em;margin-top:4px">Consistency</div>
      </div>
    </div>
  </div>
  <div style="background:#fff;border-radius:12px;padding:16px;margin-bottom:16px;border:1px solid #e5e5ea">
    <div style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #e5e5ea">
      <span style="font-size:13px;color:#8e8e93">Days tracked</span>
      <span style="font-size:14px;font-weight:500;color:#1d1d1f">${data.tracked}/${data.total}</span>
    </div>
    <div style="display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #e5e5ea">
      <span style="font-size:13px;color:#8e8e93">Current streak</span>
      <span style="font-size:14px;font-weight:500;color:#F59E0B">${data.streak} days</span>
    </div>
    <div style="display:flex;justify-content:space-between;align-items:center;padding:8px 0">
      <span style="font-size:13px;color:#8e8e93">Best streak</span>
      <span style="font-size:14px;font-weight:500;color:#22C55E">${data.bestStreak} days</span>
    </div>
  </div>
  <div style="text-align:center;padding:16px 0">
    <a href="https://app.scottzwills.com" style="display:inline-block;padding:12px 28px;background:#1d1d1f;color:#fff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:500">Open Win the Day</a>
  </div>
  <p style="text-align:center;font-size:11px;color:#8e8e93;margin-top:20px">You're receiving this because you enabled reports in Win the Day.</p>
</div>
</body>
</html>`;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { type, data } = (await req.json()) as {
      type: "weekly" | "monthly";
      data: ReportData;
    };

    if (!type || !data) {
      return new Response(JSON.stringify({ error: "Missing type or data" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const email = data.email;
    if (!email) {
      return new Response(JSON.stringify({ error: "Missing email in data" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const html =
      type === "weekly"
        ? generateWeeklyEmailHTML(data as WeeklyReportData)
        : generateMonthlyEmailHTML(data as MonthlyReportData);

    const subject =
      type === "weekly"
        ? `Win the Day - Weekly Report (${data.label})`
        : `Win the Day - Monthly Report (${data.label})`;

    // Try to send via Resend API
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail = Deno.env.get("REPORT_FROM_EMAIL") || "Win the Day <reports@scottzwills.com>";

    if (resendKey) {
      const resendRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${resendKey}`,
        },
        body: JSON.stringify({
          from: fromEmail,
          to: [email],
          subject,
          html,
        }),
      });

      if (!resendRes.ok) {
        const errBody = await resendRes.text();
        console.error("Resend API error:", errBody);
        return new Response(
          JSON.stringify({ error: "Failed to send email", details: errBody }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const resendData = await resendRes.json();
      return new Response(
        JSON.stringify({ success: true, messageId: resendData.id }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Fallback: no Resend key — return the report data and HTML as JSON
    console.warn("RESEND_API_KEY not set — returning report as JSON fallback");
    return new Response(
      JSON.stringify({
        success: true,
        fallback: true,
        message: "Resend API key not configured. Report generated but not emailed.",
        subject,
        html,
        data,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("send-report error:", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
