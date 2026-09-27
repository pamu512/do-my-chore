# Do My Chore — Devpost draft (Build With AI: Basics)

> **Status:** DRAFT ONLY. Do **not** Final Submit without Anoop. Video URL is TBD until the demo is recorded.
> Hackathon: https://learn-ai-basics.devpost.com/ · Deadline: Oct 26, 2026 @ 5:00pm EDT

## Paste into Devpost

### Project name
Do My Chore

### Tagline / Elevator pitch (one line)
Parent sets the goal, AI plans the save, kids earn it.

### Repo URL
https://github.com/pamu512/do-my-chore

### Demo video URL
_TBD — record from `docs/demo-video-script.md` (1–3 min, YouTube or Vimeo, public)_

### Built With
- Flutter
- Dart
- Supabase (Auth, Postgres + RLS, Storage, Edge Functions)
- OpenAI (optional; both AI moments have deterministic zero-key fallbacks)
- Devpost Learn Skill Pack planning docs (`scope.md`, `prd.md`, `spec.md`)

### Short description (what it does / who it's for / what you learned)

**What it does**
Do My Chore is a Flutter + Supabase proof of concept for families saving toward a real kid goal (Disneyland, camping, a game). A parent creates a goal with a cost and target date, taps **Suggest plan**, and gets an AI-drafted weekly top-up, 4–8 chores, and a plain-language "why". Kids complete chores (camera when the chore needs visual proof). The parent approves or rejects with a nudge. Approvals credit a **goal bank**; overshoot fills the goal to target and the remainder lands in the kid's **pocket**. Approved photos can join a deletable **Goal Album**.

The demo uses one seeded family and an in-app Parent ↔ Kid role switch so the full loop films in 1–3 minutes without login friction.

**Who it's for**
Parents who want a clear save plan and kids who want the progress bar to move when they finish a chore. Judges/reviewers: watch the video — it shows the end-to-end loop; the public repo has planning docs and run instructions.

**What I learned**
Planning before code mattered: `scope.md` / `prd.md` / `spec.md` locked non-goals (no banking rails, no COPPA claims, parent always final on photo assist) so the agent didn't invent product surface. Treating `ledger_entries` as the only money source of truth (balances summed on read, overshoot split in one transaction) kept the demo honest and testable. Building both AI moments with **deterministic fallbacks and zero API keys** meant the demo stays filmable even when keys are missing. Skills + design-first beat "prompt until it works."

### Longer "About the project" (optional paste)

**The problem**
Families want kids to earn toward real goals, not a vague allowance. Parents need a plan (cost, weeks, chores, top-ups). Kids need clear "done" and visible progress.

**The demo loop**
1. Parent creates goal → AI Suggest plan (weekly top-up + chores + why) → edit → accept
2. Role switch to Kid → Today → mark done (photo when required)
3. Role switch back → approve, or reject with a nudge (chore returns to Kid Today)
4. Ledger credits goal bank vs pocket; progress bar fills
5. Approved photos → Goal Album (any item deletable)

**Architecture**
- Flutter app (iOS simulator primary) with Parent ↔ Kid role switch
- Supabase Auth, Postgres with RLS on every family-scoped table, Storage for photos, Edge Functions for Suggest plan + Photo assist
- `ledger_entries` is the money source of truth
- Both AI moments run with zero keys; set `OPENAI_API_KEY` to upgrade

**Honesty (must stay in submission copy)**
- The ledger is in-app only. Not a bank, card, or payment rail. Parents settle real money offline.
- Demo photos and kid accounts are **test data only**. This POC does not implement COPPA-style verifiable parental consent.
- Photo assist only *suggests*; the parent is always final. No verification-accuracy claims.

**How to run (for anyone cloning)**
See README: `supabase start` + `supabase db reset`, then `flutter run` under `app/` with `SUPABASE_URL` and `SUPABASE_ANON_KEY` dart-defines. Demo accounts: `parent@demo` / `kid@demo` (password `demo1234`) — local demo only.

### Submission checklist (pre–Final Submit)
- [x] Public repo with MIT LICENSE
- [x] `scope.md`, `prd.md`, `spec.md` in repo root
- [x] README with run instructions + honesty notices
- [ ] Demo video recorded (1–3 min) and uploaded to YouTube/Vimeo — public link pasted above
- [ ] Devpost project created and fields filled from this draft
- [ ] **Final Submit only when Anoop says so**

### Notes for Anoop
- Judges won't clone or run code; the video must show it working end-to-end.
- Presentation criterion: problem, who it's for, why it matters, easy to follow.
- After video exists, paste URL here and on Devpost; keep this file as the source of truth for copy tweaks.
