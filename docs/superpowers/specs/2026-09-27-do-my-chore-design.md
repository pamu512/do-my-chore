# Do My Chore: Design Spec (Build With AI: Basics)

**Date:** 2026-09-27 (rev 2: review gaps folded same day)  
**Hackathon:** [Build With AI: Basics](https://learn-ai-basics.devpost.com/) (deadline ~2026-10-27 05:00 HKT)  
**Approach:** B: Flutter + tiny backend (Supabase)  
**Status:** Design ready for skill-pack `/scope` when scheduled; treat as **hackathon artifact**, not next portfolio product bet (chore space is crowded: Greenlight / BusyKid / Homey). Portfolio front-runners stay elsewhere (e.g. Shelter Needs). Care Ladder remains higher priority unless Anoop bumps Basics.

## 1. Problem and one-liner

Families want kids to earn toward real goals (Disneyland, camping, a game), not only a vague weekly allowance. Parents need a **plan to save** (cost, weeks, chore budget, top-ups). Kids need clear chores and visible progress.

**One-liner:** Parent sets a goal and save plan; kids do chores (with proof when required); earnings split into goal bank vs pocket; chore photos become a Goal Album.

## 2. Competitors (context)

Banking-heavy: Greenlight, BusyKid, FamZoo, Acorns Early. Tracker-only: Homey, MyChoreBoard.  
**Wedge for this hack:** Goal-first + parent plan-to-save + conditional AI photo proof + Goal Album. No real debit card in POC.  
**Strategic note:** Entrenched competitors mean this is a skill-pack / submission vehicle, not a “slim or no real products” portfolio bet.

## 3. Users and demo spine (parent-led)

1. Parent creates goal (e.g. Disneyland) with cost + target date.  
2. AI Suggest plan → chores + weekly parent top-up; parent edits and accepts.  
3. Kid sees Today chores; completes (photo if required).  
4. Parent approves (AI photo assist when `requires_photo`); rejected → chore returns to Today with a nudge.  
5. Ledger credits goal bank / pocket per split; progress bar fills (overshoot rule below).  
6. Photos feed Goal Album for that goal (deletable).

**Demo UX:** Prefer an in-app **role switch** (Parent ↔ Kid) on the seeded family, or two simulators side by side. Avoid slow login switching that eats the 1-3 min video.

Seed: `parent@demo` / `kid@demo`, one family (role switch may use one session + profile toggle for the cut).

## 4. Screens

**Parent:** Home; New Goal (+ Suggest plan); Goal detail (progress, weeks-to-goal, chores); Approval inbox; Goal Album (add from submission, delete item).  
**Kid:** Today (includes rejected-with-nudge items); Goal progress (goal vs pocket); Mark done (+ camera when required).

## 5. Data (Supabase)

- `families`, `profiles` (role `parent`|`kid`, `family_id`)  
- `goals` (title, `target_amount`, `target_date`, status; **no authoritative denormalized balance column**, see ledger)  
- `chores` (goal_id, title, `reward_amount`, `default_split_goal_pct`, **`requires_photo` bool**)  
- `chore_submissions` (status pending|approved|rejected, `photo_url` nullable, `ai_photo_result` jsonb nullable, `reject_nudge` text nullable)  
- `ledger_entries` (goal_credit | pocket_credit | parent_topup; amount; refs), **source of truth**  
- `ai_plans` (goal_id, suggestion json, accepted)  
- `album_items` (goal_id, photo_url, chore_submission_id?, caption?, added_by, created_at), **deletable**

**RLS:** Enable Row Level Security on all family-scoped tables; policies restrict read/write to rows matching the caller’s `family_id` (and role where needed). Storage paths prefixed by `family_id`.

**Balances:** Compute `goal_bank` and `pocket` from `ledger_entries` on read (demo scale). If a cached column is added later for UX, update it only inside the same DB transaction as the ledger insert.

**Overshoot rule (locked):** When a credit would push goal-bank past `target_amount`, credit only enough to reach the target into `goal_credit`; **remainder overflows to `pocket_credit`** in the same approval/top-up transaction. Progress bar caps at 100%.

**Rejected submissions:** Status `rejected` returns the chore to Kid Today with a short nudge (e.g. “Try again with a clearer photo of the clean table”). Kid can resubmit (new submission row).

**Money honesty:** In-app ledger only; UI copy: parent settles real money outside the app. No spend/withdrawal product in POC (pocket is display + overflow sink; cash-out is offline).

## 6. AI moments

1. **Suggest plan** (required): inputs goal title, amount, date, kid age → weekly top-up + 4-8 chores + **“why this plan” in plain parent language** (no ML jargon). Deterministic fallback if no LLM key. Prefer marking `requires_photo` only on visually verifiable chores in the suggestion.  
2. **Photo assist** (when `requires_photo`): vision suggests approve/reject for **visually verifiable** chores only (“cleaned the table” yes; “read a chapter” no, those must not require photo). **Parent always final.**  
3. Honesty: do not claim perfect verification, COPPA compliance, or banking AI.

## 7. Stack

- New empty folder / new public GitHub repo (Basics rule: no old code).  
- Flutter (iOS simulator primary for demo video).  
- Supabase: Auth, Postgres **with RLS**, Storage (photos), Edge Function for AI.  
- Skill pack artifacts in repo: `scope.md`, `prd.md`, `spec.md` (from Devpost Learn skills).

## 8. Non-goals

- Real cards / KYC / bank rails / in-app cash-out  
- ReadyPup / Care Ladder code reuse  
- App Store submit for Basics  
- Multi-tenant billing  
- Unsupervised AI auto-approve or auto-pay without parent  
- **Kids’ data privacy productization:** COPPA-style verifiable parental consent flows **out of scope for POC**; photos and kid accounts in the demo are **test/demo data only**. Post-hackathon, under-13 + cloud photos implies real consent constraints.

## 9. Success criteria

- Parent-led 1-3 min video shows full loop: AI plan → assign → kid done (with and without required photo) → approve/reject+redo → bars fill with overshoot-to-pocket if shown → album add/delete.  
- Public repo with skill-pack planning docs + README.  
- Seeded demo family works on simulator against Supabase with RLS on.  
- No banking or kids-privacy compliance claims in copy.

## 10. Priority note

Care Ladder (Amazon / Galuxium / OpenCV) remains higher priority unless Anoop bumps Basics. This spec is ready for skill-pack `/onboard` → `/scope` onward when scheduled.
