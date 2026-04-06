# ManyChat Webhook Setup — Setter Tracking

This connects ManyChat to your Pipeline dashboard so you can track setter activity, follow-ups, response speed, and book rate automatically.

## Step 1: Run the SQL in Supabase

1. Go to [Supabase Dashboard](https://supabase.com/dashboard) > SQL Editor
2. Paste the contents of `supabase-setter-events.sql` and click **Run**

This creates the `setter_events` table and webhook function.

## Step 2: Set Your Webhook Secret

In Supabase SQL Editor, run:
```sql
ALTER DATABASE postgres SET app.manychat_webhook_secret = 'YOUR_SECRET_HERE';
```
Replace `YOUR_SECRET_HERE` with a random string. You'll use this same secret in all 3 ManyChat flows below.

## Step 3: Create 3 ManyChat Flows

You need 3 separate flows in ManyChat, each with an **External Request** action.

### Flow 1: New DM Received
- **Trigger:** "New Conversation Started"
- **Action:** External Request (POST)

### Flow 2: Setter Replied
- **Trigger:** "Live Chat Agent Sends Message" (or whichever trigger fires when your setter responds)
- **Action:** External Request (POST)

### Flow 3: Lead Booked
- **Trigger:** Tag "booked" is applied (or whatever tag you use when a call is confirmed)
- **Action:** External Request (POST)

### Settings for ALL 3 Flows

**Request Type:** POST

**URL:**
```
https://ceahoxydtjcprjkbjakn.supabase.co/rest/v1/rpc/receive_setter_event
```

**Headers:**

| Header | Value |
|--------|-------|
| Content-Type | application/json |
| apikey | (Your Supabase anon key — find in Dashboard > Settings > API) |

**Body (JSON):**

For **Flow 1 (New DM)**:
```json
{
  "webhook_secret": "YOUR_SECRET_HERE",
  "event_type": "new_dm",
  "subscriber_id": "{{id}}",
  "subscriber_name": "{{first_name}} {{last_name}}",
  "ig_username": "{{ig_username}}",
  "email": "{{email}}",
  "tags": ""
}
```

For **Flow 2 (Setter Reply)**:
```json
{
  "webhook_secret": "YOUR_SECRET_HERE",
  "event_type": "setter_reply",
  "subscriber_id": "{{id}}",
  "subscriber_name": "{{first_name}} {{last_name}}",
  "ig_username": "{{ig_username}}"
}
```

For **Flow 3 (Booked)**:
```json
{
  "webhook_secret": "YOUR_SECRET_HERE",
  "event_type": "booked",
  "subscriber_id": "{{id}}",
  "subscriber_name": "{{first_name}} {{last_name}}",
  "ig_username": "{{ig_username}}"
}
```

**Publish** all 3 flows.

## How It Works

- **New DM** → logs event + auto-creates a lead in the pipeline
- **Setter Reply** → logs event, used to calculate response speed and follow-up status
- **Booked** → logs event + updates lead status to "booked"
- **Dashboard** shows: setter activity today, who needs follow-up, avg response time, qualification + book rate
- All data flows automatically from ManyChat — no manual entry needed

## What You See in the Dashboard

1. **Setter Activity** — replies sent today, new DMs, active convos, 7-day chart
2. **Needs Follow-Up** — leads waiting for a reply, sorted by wait time
3. **Response Speed** — average time to reply, breakdown by speed tier
4. **Qualification & Book Rate** — qualified leads, book rate %, conversion funnel
