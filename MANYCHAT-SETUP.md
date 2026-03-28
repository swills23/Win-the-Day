# ManyChat Webhook Setup — Auto-Import Leads

This connects ManyChat to your Pipeline tracker so every new DM conversation automatically appears as a lead.

## Step 1: Run the SQL in Supabase

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Click **SQL Editor** in the left sidebar
4. Open the file `supabase-setup.sql` from this repo
5. Paste the entire contents and click **Run**

This creates the `pipeline_leads` table, webhook function, and migrates any existing leads.

## Step 2: Enable Realtime

1. In Supabase Dashboard, go to **Database > Replication**
2. Find `pipeline_leads` in the table list
3. Toggle it **ON**

This enables live updates — new leads appear instantly without page refresh.

## Step 3: Set Up ManyChat Flow

1. Open [ManyChat](https://manychat.com) and go to **Automation > Flows**
2. Create a new flow called **"Pipeline Auto-Import"**
3. Set the trigger to **"New Conversation Started"** (or whichever trigger you want)
4. Add an **External Request** action with these settings:

**Request Type:** POST

**URL:**
```
https://ceahoxydtjcprjkbjakn.supabase.co/rest/v1/rpc/receive_manychat_lead
```

**Headers:**
| Header | Value |
|--------|-------|
| Content-Type | application/json |
| apikey | eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNlYWhveHlkdGpjcHJqa2JqYWtuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzOTAyNDMsImV4cCI6MjA4OTk2NjI0M30.B9SPHoEYWd_-GtaNuXrc8M0tlqhxns9otKl9z5jcTZ0 |

**Body (JSON):**
```json
{
  "webhook_secret": "57aaa337c2989b44cb28fd25655b770df35f49a6b5e93e50",
  "subscriber_id": "{{id}}",
  "subscriber_name": "{{first_name}} {{last_name}}",
  "ig_username": "{{ig_username}}",
  "email": "{{email}}",
  "tags": "",
  "lead_source": "dm_first",
  "source_keyword": ""
}
```

> The `{{id}}`, `{{first_name}}`, etc. are ManyChat template variables — they auto-fill with the subscriber's data.

5. **Publish** the flow

## Step 4: Bulk Sync Existing Subscribers

1. Go to your Pipeline dashboard at app.scottzwills.com
2. Scroll to the ManyChat Integration section
3. Click **"Sync all ManyChat subscribers"**
4. Wait for the scan to complete (it searches A-Z to find all subscribers)

## How It Works

- **New conversations:** ManyChat fires the webhook → lead appears in Pipeline instantly
- **Existing subscribers:** Bulk sync discovers them via API search and imports them
- **Duplicates:** Handled automatically — same subscriber won't be added twice
- **Live updates:** Supabase Realtime pushes new webhook leads to your browser without refresh

## Lead Badges

- **AUTO** (green) — Auto-imported via ManyChat webhook
- **SYNC** (orange) — Imported via bulk sync button
- **MC** (blue) — Manually added but linked to ManyChat subscriber
