# Goal-first Nebius AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Do not start coding until Anoop explicitly says to implement.** This document is plan + requirements + fallbacks only.

**Goal:** Let a parent type a plain-language goal and get a save-cost estimate plus a primary-kid chore plan via Nebius Token Factory / Nemotron (with zero-key Basics-safe fallbacks), without trip booking and without selling or advertising on family data.

**Architecture:** Keep work on existing repo branch `feat/nebius-token-factory` (draft PR #3). Reuse `_shared/llm.ts` and edge functions. Shift cost estimate earlier in the Flutter parent flow so it runs from goal text + primary kid age, then return chores in the same review step. Parent remains final; Photo Assist unchanged in spirit.

**Tech Stack:** Flutter (app/), Supabase Postgres + RLS + Storage, Deno Edge Functions, Nebius Token Factory (Nemotron), optional OpenAI, optional Tavily.

**Spec:** `docs/superpowers/specs/2026-09-28-nebius-ai-privacy-design.md`

## Global Constraints

- **No GitHub fork.** Same repo `pamu512/do-my-chore`. Branch: `feat/nebius-token-factory` (PR #3). Optional later: a second feature branch off this one if we need to split docs from product code; still not a fork.
- **Do not block Build With AI: Basics.** `DEMO_WALK=true` and zero API keys must still complete the Basics demo loop.
- **Merge gate:** do not merge PR #3 until Basics demo video URL is on the Basics Devpost draft **or** Do My chore agent / Anoop gives explicit OK.
- **Final Submit:** Nebius Devpost Final Submit only with Anoop present.
- **Privacy:** never sell family/AI data; never use it for advertising; prompts never include names, emails, auth uids, family ids, ledger, or addresses.
- **Kid context v1:** primary / selected kid age only. Multi-kid chore plans = stretch only.
- **Not in scope:** travel itinerary, flights, hotels, bookings, payment rails, COPPA-grade consent (honesty notice only for POC).
- **Copy:** weekly save = parent funding real cost; must not read as kid pocket money. No em dashes in user-facing copy.
- **Secrets:** `NEBIUS_API_KEY`, optional `OPENAI_API_KEY`, optional `TAVILY_API_KEY`, optional model overrides — Supabase function secrets only, never git or Flutter `--dart-define`.
- **Provider order:** Nebius → OpenAI → deterministic / abstain (existing `_shared/llm.ts`).

---

## Fork / branch decision

| Option | Use? | Why |
|---|---|---|
| Fork `pamu512/do-my-chore` to another GitHub account/org | **No** | You own the repo; dual-submit and PR review stay simpler on one remote. |
| New orphan repo | **No** | Loses Basics history, seed, and dual-submit story. |
| Continue `feat/nebius-token-factory` (PR #3) | **Yes (default)** | Eligibility wiring + privacy design already here; goal-first is a UX/API sequence change on top. |
| Extra branch `feat/goal-first-ux` off PR #3 tip | **Optional** | Only if we want a nested PR into #3 for review isolation. Not required for v1. |

**Action now:** do **not** create a fork. Stay on PR #3.

---

## Requirements

### R1 — Parent goal-first input

- Parent provides free-text goal (required). Amount is **not** required up front.
- App attaches primary / selected kid age automatically.
- If deadline cannot be inferred (e.g. “sometime next year”), UI may ask **one** clarifying date; otherwise derive weeks from text (e.g. Christmas → next 25 Dec).

### R2 — AI outputs before Accept

Single review surface must show:

1. Cost estimate: `low`, `likely`, `high`, currency, short rationale, `provider` (`nebius` | `openai` | `deterministic`)
2. `weekly_save_suggestion`
3. Optional deals list when Tavily configured (else empty + `deal_search: skipped`)
4. Chore plan: 4–8 chores, weights sum ≥ 100, `requires_photo` only when visually checkable, `why` in plain parent language
5. Source badge: live model vs deterministic fallback (honest UI)

### R3 — Parent control

- Parent can override locked amount (default likely) and edit chores before Accept.
- Accept locks `goals.target_amount`, plan `weekly_parent_save`, stores `cost_estimate` / `deal_snapshot` under RLS.
- AI never auto-approves chores or writes ledger entries.

### R4 — Photo Assist (unchanged contract)

- Suggest only on Approvals when photo exists and chore is visually checkable.
- Abstain otherwise; parent final.
- Payload: chore title + image only (no names).

### R5 — Basics safety

- Zero keys → full path with deterministic estimate + catalogs.
- `DEMO_WALK=true` → local builders only; skip network estimate sheet friction that would break the video script (keep scriptable path).
- Existing Basics Devpost docs (`docs/demo-video-script.md`, `docs/devpost-draft.md`) must not be forced to mention Nebius.

### R6 — Privacy / ads

- Documented promise in design + in-app one-liner near first AI call.
- Edge logs: provider, model, latency, success/fallback only — never keys or image bytes.
- Privacy backlog items (EXIF strip, short-TTL signed URLs) tracked as tasks below; block “real families” messaging until done, not the hackathon POC demo with synthetic data.

### R7 — Hackathon eligibility

- At least one live path uses Nebius Token Factory + NVIDIA open model when `NEBIUS_API_KEY` is set.
- Demo video / Devpost for Nebius must name Nebius + Nemotron when that project is created (separate from Basics; create only when story is real).

---

## Contingency / fallback matrix

| Failure or gap | User-visible behavior | Engineering fallback |
|---|---|---|
| No `NEBIUS_API_KEY` | Plan still works | OpenAI if set; else deterministic cost bands + age catalogs |
| No `OPENAI_API_KEY` either | Plan still works | Deterministic only |
| Nebius / OpenAI HTTP error, timeout, bad JSON | Soft degrade | Client timeout (8–12s) → local deterministic; never hard-fail create-goal |
| Vision model id wrong / vision fails | Approvals still work | Photo Assist abstain with clear reason |
| No `TAVILY_API_KEY` or Tavily error | Estimate + chores still show | `deals: []`, `deal_search: skipped` |
| Goal text too vague for date | May ask one date | Default 12 weeks if parent skips (document in UI) |
| Goal text has no money clue | Estimate still returns | LLM prior or deterministic default band table by `goal_mode` (trip vs item); parent must confirm before lock |
| `DEMO_WALK=true` | Video path unchanged | Skip live invoke; local builders only |
| Edge function not deployed | App still works | `edge_ai_client.dart` catch → local |
| PR #3 merge blocked by Basics | Nebius work continues on branch | Keep PR draft; dual-submit from branch demo if needed; merge later |
| Flutter analyze/test not on CI image | Do not claim green | Run locally on Anoop machine before merge |
| Multi-kid request | Stretch | v1 uses primary kid only; copy may say “for [primary kid]” |
| Provider retention / ads concern | Product promise | Minimize prompts; no ad SDKs; no sale; disclose third parties in privacy one-liner |

**Deterministic cost when amount unknown (required rule for planners):**

- Prefer LLM estimate from goal text when a key exists.
- Else use a small static prior table by `goal_mode` (e.g. `family_trip` vs `kid_item`) × optional duration bucket, still returning low/likely/high, then parent must confirm. Exact table values are chosen at implementation time and covered by unit tests; do not invent live market prices in the zero-key path.

---

## File map (expected touch set)

**Already on branch (reuse):**

- `supabase/functions/_shared/llm.ts`
- `supabase/functions/_shared/deals.ts` (if present)
- `supabase/functions/suggest-plan/index.ts`
- `supabase/functions/goal-cost-orchestrate/index.ts`
- `supabase/functions/photo-assist/index.ts`
- `supabase/migrations/20260928010000_goal_cost_deal.sql`
- `app/lib/services/edge_ai_client.dart`
- `app/lib/services/cost_estimate.dart` (and related)
- `app/lib/features/parent/cost_deal_sheet.dart`
- `docs/nebius-token-factory.md`
- `docs/superpowers/specs/2026-09-28-nebius-ai-privacy-design.md`

**Likely modify for goal-first:**

- `supabase/functions/suggest-plan/index.ts` — accept goal text without requiring parent amount; return estimate + plan together **or** orchestrate internal call to cost helper
- `supabase/functions/goal-cost-orchestrate/index.ts` — allow missing `targetAmount` (estimate-from-text mode)
- `app/lib/services/edge_ai_client.dart` / `ai_service.dart` / `goal_service.dart` — new invoke shape
- `app/lib/features/parent/` New Goal UI — goal-first fields; wire estimate+plan review before Accept
- `app/lib/features/parent/cost_deal_sheet.dart` — fold into pre-Accept review or keep as step 2 of same flow
- Deno tests under `supabase/functions/_shared/`
- Flutter tests under `app/test/`
- `docs/nebius-token-factory.md` — goal-first sequence + privacy one-liner
- Optional: EXIF strip on photo upload path under `app/lib/services/` or storage helper

**Do not touch unless needed for compile:** Basics-only demo script intent; avoid rewriting `docs/demo-video-script.md` to require Nebius.

---

## API contract (target)

### `POST /functions/v1/suggest-plan` (goal-first)

**Request (minimized):**

- `goalText` (string, required) — parent free text (may also accept legacy `title`)
- `kidAge` (number, required)
- `targetDate` (string YYYY-MM-DD, optional)
- `targetAmount` (number, optional) — if present, treat as parent prior; if absent, model/deterministic estimates
- `goalMode` (optional hint)

**Response:**

- `estimate`: `{ low, likely, high, currency, rationale, provider }`
- `weekly_save_suggestion`: number
- `weeks`: number
- `slots` (optional): `{ goal_mode, place?, duration_days?, party_size_default? }`
- `weekly_parent_save`, `chores[]`, `why` (existing plan fields)
- `deals` / `deal_search` — either here or only from cost orchestrate; pick one place in Task 2 and stay consistent

### `POST /functions/v1/goal-cost-orchestrate`

Keep for deal refresh / re-estimate; align body so `targetAmount` optional when `goalText`/`title` present.

### `POST /functions/v1/photo-assist`

Unchanged: `{ choreTitle, image? }` → `{ suggest, reason }`.

---

### Task 1: Lock plan doc on branch (docs only)

**Files:**

- Create: `docs/superpowers/plans/2026-09-28-goal-first-nebius.md` (this file)

**Requirements:** Plan committed to `feat/nebius-token-factory`; no application code in this task.

- [ ] **Step 1:** Add this markdown path on the branch via docs-only commit.
- [ ] **Step 2:** Verify PR #3 lists the new plan file.
- [ ] **Step 3:** Stop. Wait for Anoop “implement” before Task 2+.

**Done when:** Plan visible on PR #3; zero Flutter/Deno behavior changes in the commit.

---

### Task 2: Edge contract — estimate without required amount

**Files:**

- Modify: `supabase/functions/goal-cost-orchestrate/index.ts`
- Modify: `supabase/functions/suggest-plan/index.ts`
- Modify/Create: Deno tests beside `_shared` / function tests
- Modify: `docs/nebius-token-factory.md` (request/response section)

**Interfaces:**

- Consumes: existing `chatCompletions`, `parseJsonObject`, deterministic helpers
- Produces: JSON matching API contract above; never requires PII fields

**Requirements:**

- If `targetAmount` missing/invalid and LLM available → estimate from goal text + slots.
- If LLM unavailable → deterministic prior by `goal_mode` (see contingency matrix); still return valid bands.
- Suggest-plan returns chores + estimate in one response **or** documents a strict two-call client sequence; prefer one response for parent UX.
- Prompts include only allowed fields (spec §5.4).
- Unit tests: provider order unchanged; missing amount path; bad JSON → fallback; think-block strip still works.

**Fallbacks:** Any LLM failure → deterministic path; never 500 on “no key”.

- [ ] **Step 1:** Write failing Deno tests for missing `targetAmount` + zero-key deterministic estimate.
- [ ] **Step 2:** Run tests; confirm fail for the right reason.
- [ ] **Step 3:** Implement minimal edge changes to satisfy tests (when Anoop says implement).
- [ ] **Step 4:** `deno test` / `deno check` green.
- [ ] **Step 5:** Commit edge + tests + doc note only.

**Done when:** Curl/invoke shapes documented; tests cover key/no-key/missing-amount.

---

### Task 3: Flutter client + goal-first UI wiring

**Files:**

- Modify: `app/lib/services/edge_ai_client.dart` (and `ai_service.dart` / `goal_service.dart` as needed)
- Modify: parent New Goal screens under `app/lib/features/parent/`
- Modify: `app/lib/features/parent/cost_deal_sheet.dart` (merge into pre-Accept review or call earlier)
- Test: `app/test/` (extend cost / plan tests)

**Requirements:**

- New Goal: prominent goal text; amount optional; primary kid age from family context.
- On “Suggest”: invoke new contract; show estimate + chores + optional deals; allow edit; Accept locks.
- Timeouts + catch → local deterministic (existing pattern in `edge_ai_client.dart`).
- `DEMO_WALK` → local only.
- Privacy one-liner near first AI call (no ads / no sale; what leaves the device).
- Copy: parent save ≠ kid pocket money.

**Fallbacks:** Network/function errors → local plan + local cost bands; UI must explain “offline estimate”.

- [ ] **Step 1:** Write/extend Flutter unit tests for parsing combined response + DEMO_WALK skip.
- [ ] **Step 2:** Implement client invoke + UI review flow (when implementing).
- [ ] **Step 3:** `flutter test` / `flutter analyze` on a machine with SDK.
- [ ] **Step 4:** Commit.

**Done when:** Manual path: type Miami Christmas goal with no amount → see bands + chores → Accept persists amount.

---

### Task 4: Photo Assist privacy hygiene (POC-hardening)

**Files:**

- Photo upload / storage helper under `app/lib/services/` (locate existing upload)
- `photo-assist` only if logging changes needed

**Requirements:**

- Strip GPS/EXIF on upload when feasible in Dart.
- Confirm signed URLs short-lived; no image base64 in logs.
- Abstain path unchanged.

**Fallbacks:** If EXIF strip library is too heavy for hackathon, document as known gap in honesty notes; do not block Nebius eligibility demo on synthetic photos.

- [ ] **Step 1:** Audit upload path; note current EXIF behavior.
- [ ] **Step 2:** Implement strip or document gap explicitly in `docs/nebius-token-factory.md`.
- [ ] **Step 3:** Commit.

**Done when:** Either strip verified or gap documented (no silent claim of EXIF safety).

---

### Task 5: Secrets, smoke, dual-submit packaging

**Files / ops:**

- Supabase secrets (hosted project used for demo)
- `docs/nebius-token-factory.md`
- Nebius Devpost project (create only when demo story ready)
- Coordinate with Do My chore agent on Basics video gate

**Requirements:**

- Set `NEBIUS_API_KEY` on demo project; optional Tavily.
- Smoke: suggest-plan with key → `provider: nebius`; without key → deterministic.
- Smoke: photo-assist abstain without key; suggest with key if vision id works (`NEBIUS_VISION_MODEL` override contingency).
- Keep PR draft until merge gate clears.
- Nebius Devpost: name Nebius + Nemotron; ≤3 min video; Final Submit with Anoop.

**Fallbacks:** Vision catalog mismatch → set `NEBIUS_VISION_MODEL` or keep abstain and still show text eligibility via suggest-plan / cost. Basics submit remains on separate Devpost project.

- [ ] **Step 1:** Checklist secrets on demo project (Anoop confirms).
- [ ] **Step 2:** Record smoke results in PR comment (provider used, fallbacks hit).
- [ ] **Step 3:** After Basics gate, merge PR #3.
- [ ] **Step 4:** Nebius Devpost draft + submit only with Anoop.

**Done when:** Live smoke noted; merge/submit per gates.

---

### Task 6 (stretch, not v1): Multi-kid chore plans

Deferred. When picked up: separate plan; still no PII in prompts; per-kid ages only.

---

## Test plan (summary)

| Layer | Command / check | Expect |
|---|---|---|
| Deno shared | `deno test supabase/functions/_shared` | Pass (provider order, parse, deals, missing-amount) |
| Deno check | `deno check` on llm + three functions | ok |
| Flutter | `flutter test`, `flutter analyze` | Pass on SDK machine |
| Manual zero-key | Unset keys, create goal from text only | Deterministic estimate + chores |
| Manual Nebius | Set `NEBIUS_API_KEY` | `provider: nebius` on estimate/plan |
| Manual DEMO_WALK | `--dart-define=DEMO_WALK=true` | No network plan; scriptable |
| Manual Photo Assist | Trust chore vs clean chore | Abstain vs suggest; parent final |
| Privacy grep | Prompts in edge fns | No name/email/uid fields |

---

## Execution order and stop rules

1. **Now:** Task 1 only (this plan on the branch). **No application code.**
2. **After Anoop says implement:** Tasks 2 → 3 → 4.
3. **Task 5** when ready to demo; merge only after Basics gate.
4. If Basics is at risk, pause Nebius UI changes that alter `DEMO_WALK` path; prefer additive UI behind the same local fallbacks.

---

## Success criteria

- No fork created; work on PR #3.
- Parent types goal only → estimate + primary-kid chores → Accept.
- Contingency matrix behaviors verified (especially zero-key and DEMO_WALK).
- Privacy promise (no ads / no sale) reflected in docs and UI one-liner.
- Basics unblocked; Nebius eligibility demonstrable with Token Factory when key set.
