# Win-the-Day — Claude Code Onboarding Brief

## Project Overview
This is the business infrastructure for Scott Wills' coaching brand. The core product is 1:1 coaching focused on identity-level transformation — not discipline, not habits, not willpower. The methodology rewires the predictive models and identity patterns that drive self-sabotage cycles.

**Site:** app.scottzwills.com
**Repo:** github.com/swills23/Win-the-Day
**Branch strategy:** main = production (auto-deploys via Vercel)

---

## Tech Stack

| Layer | Tool | Notes |
|-------|------|-------|
| Frontend | Static HTML (index.html) | Single-page app, minimal framework |
| Hosting | Vercel | Auto-deploys from GitHub main branch |
| Database | Supabase | Backend/database layer |
| Domain | GoDaddy | app.scottzwills.com |
| DM Management | ManyChat Pro | Setter uses this — has full API access |
| Booking | Calendly | Leads book calls here after setter qualifies |
| Content Scripts | Google Docs | Current script storage (migrating to AI-generated) |
| Instagram | Business Account | Drawing videos, carousels, stories |
| Version Control | GitHub | PAT available for API pushes |

---

## Business Context

### What Scott Does
Scott coaches high-agency men who know what they should be doing but can't consistently do it. They've tried discipline, habits, systems — and keep cycling back. His methodology targets the identity layer and predictive models underneath the behavior, not the behavior itself.

### The Funnel
1. **Instagram content** (drawing videos, carousels, stories) drives traffic
2. **Profile** (bio, highlights, 3 pinned posts) converts visitors to DMs
3. **Setter** qualifies leads via ManyChat DMs
4. **Calendly** books qualified leads onto sales calls
5. **Scott closes** on the call

### Key Metrics That Matter
- Which content pieces drive DMs (not just likes/views)
- DM-to-booked-call conversion rate
- Which setter conversations convert vs. drop off
- Content format performance (drawing video vs. carousel vs. story)

---

## Brand Voice & Language

### Core Positioning
Anti-discipline. The entire brand is built on the idea that discipline is a bandaid — it doesn't address the deeper identity or predictive models driving behavior. Change happens at the identity level, not the habit level.

### Key Frameworks & Language
- **The Loop:** Momentum → Collapse → Shame → Restart (Scott's personal story: 23 times over 5.5 years, documented in a journal)
- **Predictive Models:** The brain runs predictions based on identity — behavior follows identity, not willpower
- **Rewiring:** Not managing or suppressing patterns, but actually rewriting them at the root
- **The Gap:** The space between knowing what to do and being able to consistently do it — this is where Scott's audience lives
- **Identity-level change:** "I didn't become more disciplined. I became a different person."

### Tone
- Direct, no fluff
- Uses analogies heavily (beach ball underwater, thermostat, mopping while faucet runs)
- Speaks from lived experience, not theory
- Casual but confident — not corporate, not guru
- Never uses: "hustle," "grind," "just be consistent," or any generic motivation language

### Words/Phrases Scott Actually Uses
- "It wasn't pretty"
- "Something underneath was running the show"
- "The gap between knowing and doing"
- "Rewire the pattern"
- "You're not lacking discipline — you're running a pattern you don't see"

---

## What We're Building (Infrastructure Roadmap)

### Phase 1: DM Pipeline Tracker (BUILD FIRST)
**Purpose:** Track every DM conversation with source attribution, demographics, conversation quality, and conversion outcome.
**Data sources:** ManyChat Pro API, Instagram Business API
**Key fields per lead:**
- Source content (which post/story/reel drove the DM)
- Lead demographics
- Conversation transcript summary
- Setter responses and approach used
- Objections raised
- Outcome (booked / ghosted / not qualified / closed)
- Time from first DM to booked call
**Output:** Dashboard showing which content produces buyers, what setter approaches convert, and where leads drop off.

### Phase 2: Content Intelligence Engine
**Purpose:** Proactively scan and analyze Scott's Instagram content performance to identify what's working and why.
**Data sources:** Instagram Business API, scraping tools for richer data
**Analysis targets:**
- Hook performance (first line / first 3 seconds)
- Topic/angle patterns that drive saves, shares, DMs
- Format performance (drawing video vs. carousel vs. story)
- Posting time optimization
- Comment sentiment and engagement quality
- Competitor/niche content patterns (future)
**Output:** Weekly content intelligence reports with specific, actionable insights — not vanity metrics.

### Phase 3: AI Script Generator
**Purpose:** Generate drawing video scripts optimized based on Phase 2 data — what's actually working.
**Inputs:** Winning patterns from content analysis, Scott's voice/frameworks, trending angles
**Outputs:** Ready-to-film drawing video scripts in Scott's exact voice and style
**Goal:** Save 10-20 hours/week in ideation and scripting. Eliminate the mental load of "what should I post."

---

## Coding Conventions

- Keep it simple — Scott is not a developer. Everything should be maintainable and understandable.
- HTML/CSS/JS for frontend unless a framework is clearly needed
- Supabase for all database needs — no additional backend services unless absolutely necessary
- All environment variables and API keys stored securely (never hardcoded)
- Mobile-first design — Scott's audience is on phones
- Every feature should have a clear UI that Scott can use without technical knowledge
- Comment code thoroughly — future Claude sessions need to understand what was built and why

---

## Working With This Project

### Before You Build Anything:
1. Read this entire file
2. Check the current state of index.html and any other files in the repo
3. Understand which phase of the roadmap the task falls under
4. If the task is ambiguous, ask for clarification before writing code

### After Every Change:
1. Test locally or verify the build succeeds
2. Ensure the change doesn't break existing functionality on app.scottzwills.com
3. Write clear commit messages describing what changed and why

### Important Notes:
- This is a live business site — don't push breaking changes to main
- Scott's audience sees this site — design and copy quality matter
- When in doubt, keep it simple and functional over clever and complex
- The GitHub PAT is available for API pushes — use it for automated workflows
