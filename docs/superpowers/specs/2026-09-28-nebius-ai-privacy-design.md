# Do My Chore — Nebius AI + personal-data protection design

**Status:** draft for Anoop review (28 Sep 2026)  
**Branch / PR:** `feat/nebius-token-factory` · https://github.com/pamu512/do-my-chore/pull/3  
**Track:** Nebius × NVIDIA Global AI Hackathon — Best Apps and Agents (dual-submit; must not block Build With AI: Basics)

---

## 1. Product intent (locked)

Parent types a **plain-language goal only**. The app takes planning work off their plate:

1. **Estimate** how much the family needs to save (cost bands + weekly save to a deadline).
2. **Draft** a chore plan for the **primary / selected kid** (age-appropriate habits + weights + photo flags + short why).

We do **not** plan the trip itself (no itineraries, flights, hotels, or bookings). Multi-kid chore split is a **stretch goal** only.

### Example

Parent: “I want to plan a trip to Miami with the family for 4 days for Christmas.”

App (behind the scenes): attaches primary kid age; may derive place, duration, timing, `family_trip` vs item.

AI returns: low / likely / high USD estimate, weekly save suggestion, chore plan for that kid.

Parent reviews, can override dollars or chores, then Accept.

---

## 2. Non-negotiable data promise

**Family and AI-related data is never sold and never used for advertising.**

- No selling of goals, photos, ages, ledger, or prompts.
- No ad targeting, retargeting, or broker shares from this product data.
- Data exists for **product function and inference only** (suggest plans, estimate costs, optional photo assist, optional deal search to help the parent spend under budget).
- Third-party model / search providers (Nebius Token Factory, optional OpenAI, optional Tavily) receive only the minimized fields below for a single request. We do not grant them a marketing license to our family data. Provider retention follows their API terms; we minimize what we send so there is little to retain.

This promise must appear in product honesty copy, Devpost, and any future privacy policy before real families use the app.

---

## 3. AI surfaces

| Surface | Who | When | Job | Must not |
|---|---|---|---|---|
| **Goal understand + cost estimate** | Parent | Right after goal text (before or as part of Suggest Plan) | Parse goal text into slots; estimate save amount | Book travel; invent identity; auto-lock money |
| **Suggest Plan (chores)** | Parent | Same flow | Chore list + weights + weekly save + why for primary kid | Write ledger; auto-accept |
| **Photo Assist** | Parent | Approvals when photo exists | Suggest approve / reject / abstain | Auto-approve; run on trust-only chores |
| **Deal search (optional)** | Parent | After estimate, if `TAVILY_API_KEY` set | Public web deals under likely budget | Track the family; require identity |

Parent is always final. Photo Assist is a suggestion only.

**Basics / zero-key path (required)**

- No Nebius / OpenAI → deterministic cost bands (e.g. 80 / 100 / 125% of a fallback amount or a safe default when amount is unknown) + deterministic chore catalogs by age.
- No vision key → Photo Assist abstains.
- `DEMO_WALK=true` stays local so Basics video script is unchanged.

---

## 4. Architecture

```
Flutter (anon + family RLS)
    │ JWT
    ▼
Supabase Edge Functions
    │ secrets only on server
    ├─ suggest-plan          (goal text + primary kid age → estimate + chores)
    ├─ goal-cost-orchestrate (may merge into suggest-plan for goal-first UX;
    │                         keep as separate fn if clearer for Basics)
    └─ photo-assist
         │
         ▼
    _shared/llm.ts
         ├─ NEBIUS_API_KEY → Token Factory + Nemotron
         ├─ else OPENAI_API_KEY → gpt-4o-mini
         └─ else deterministic / abstain
```

Keys never live in the Flutter binary. One provider-order policy for all LLM calls.

**Default models**

- Text: `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` (override `NEBIUS_TEXT_MODEL`)
- Vision: `nvidia/Nemotron-3-Nano-Omni` (override `NEBIUS_VISION_MODEL`)
- Thinking off; strip `<think>` before JSON parse.

---

## 5. Goal-first data flow

### 5.1 Inputs the parent provides

- Free-text **goal** (required).
- Optional explicit deadline if the text is vague (UI may ask only when parse confidence is low).

### 5.2 Inputs the app attaches (not typed each time)

- **Primary / selected kid age** (integer).
- Auth JWT for RLS (never put uid/email into the model prompt).

### 5.3 Derived slots (may be model-extracted or heuristic)

- `goal_mode`: `family_trip` | `kid_item` | other
- Destination / place (string, optional)
- Duration (e.g. nights / days)
- Target date or season (e.g. Christmas → a concrete date band)
- Party size default if not stated (document default; do not invent PII)

### 5.4 Sent to the LLM for estimate + plan

Allowed:

- Goal text (or derived slots + short restatement)
- Primary kid age
- Derived weeks to deadline
- Goal mode

Forbidden in prompts:

- Parent or kid **names**, emails, phones, auth uids, family ids
- Home address, school, device ids
- Ledger history, other kids’ profiles
- Photos (except Photo Assist path below)
- Any advertising identifiers

### 5.5 Returned to parent

- `estimate.{low,likely,high}` + currency + short rationale
- `weekly_save_suggestion`
- Chore plan: 4–8 chores, `weight_pct` sum ≥ 100, `requires_photo` only when visually checkable, `why` in plain parent language

### 5.6 On Accept / lock

Store under family RLS: target amount (locked likely or parent override), weekly save, plan, optional `cost_estimate` / `deal_snapshot` JSON.

Do **not** store raw full prompts/responses with images by default. No “AI training archive.”

---

## 6. Photo Assist (highest sensitivity)

Call vision **only if** all are true:

1. Chore is visually checkable (existing cue lists / catalogs).
2. A photo is attached.
3. A vision-capable key is configured.

Payload: chore title + ephemeral base64 image. No kid name or family id.

Otherwise abstain. Parent decides.

**Privacy backlog (before real families):** strip EXIF (esp. GPS) on upload; short-TTL signed URLs; never log image bytes.

---

## 7. Personal-data protection rules

### 7.1 Data classes

| Class | AI? | Home |
|---|---|---|
| Account (email, uid) | Never in prompts | Supabase Auth |
| Names / roles | Never in prompts | Postgres + RLS |
| Goal text / amounts / plans | Minimized fields only | Postgres + RLS |
| Kid age (primary) | Suggest / estimate only | Postgres + RLS |
| Chore photos | Vision only under gates | Storage + short signed URLs |
| Ledger | Never | Postgres |
| Provider keys | Server secrets only | Supabase secrets (not git) |

### 7.2 Required controls

1. RLS on every family-scoped table.
2. Keys only as function secrets.
3. Prompt minimization (section 5.4).
4. Parent gate on vision.
5. Human-in-the-loop on approve / lock.
6. Zero-key and DEMO_WALK fallbacks for Basics.
7. **No sale / no advertising use** (section 2).
8. Edge logs: provider, model, latency, success/fallback only — never keys, base64 images, or full photo prompts.
9. Public repo: demo data only; no real family dumps.
10. Honesty: POC is not COPPA-grade consent; required before production families.

### 7.3 Third parties

| Party | Purpose | Data | Ads / sale |
|---|---|---|---|
| Nebius Token Factory | Inference | Minimized prompts / optional image | Not permitted by our product promise; we send only inference payloads |
| OpenAI (optional fallback) | Same | Same | Same |
| Tavily (optional) | Deal URLs under budget | Generic search query from goal + budget | Same; no family identity |

We choose providers and keys; we do not build ad SDKs or sell datasets.

---

## 8. UX copy principles

- Weekly save is **parent funding the real cost**, not “kid pocket money.”
- AI “suggests”; parent decides.
- Clear line when estimate is deterministic vs live model.
- Privacy one-liner near first AI call: estimate and chore draft use the goal text and kid age; photos only if parent opens Photo Assist; we do not sell data or use it for ads.

---

## 9. Relation to draft PR #3

PR #3 already has: shared `llm.ts`, suggest-plan, photo-assist, goal-cost-orchestrate, cost/deal sheet after Accept, Nebius docs.

**Goal-first UX changes the sequence:** estimate moves earlier (from “after Accept with parent-entered amount” toward “from goal text + primary kid age”). Implementation waits for Anoop OK + Do My chore / Basics video gate. This design doc is the lock; code follows separately.

Stretch (not v1): multi-kid plans; richer party-size UI; natural-language follow-ups.

---

## 10. Success criteria

- Parent can type only a goal and get a save estimate + chore plan for the primary kid.
- No trip booking/itinerary scope creep.
- Prompts never include names, emails, or ledger.
- Photos leave the project only under Photo Assist gates.
- Documented promise: **no advertising use, no sale of family or AI data.**
- Basics zero-key / DEMO_WALK still work.
- Merge of Nebius code still waits on Basics video URL or explicit Do My chore OK; Final Submit only with Anoop present.

---

## 11. Approval

Anoop: review this file. Request edits here before any further Nebius feature code. After approval, implementation plan / code can proceed under the existing merge gate.
