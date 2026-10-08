# Do My Chore: Scope

> Hackathon: [Build With AI: Basics](https://learn-ai-basics.devpost.com/) · Authoritative design: [`docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md`](docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md) (rev 3)

## Problem

Families want kids to earn toward **real goals** - a family trip, a skateboard - not just receive a vague weekly allowance. Parents need a realistic plan to fund the cost. Kids need clear habits and visible progress. Allowance apps either gamify chores with fake money or hand kids a debit card.

## One-liner

The kid earns the goal 100% through weighted habit chores; the parent funds the real cost with an AI-planned save schedule. Chore photos become a deletable **Goal Album**.

## Users

| User | What they do |
|---|---|
| **Parent** | Creates goal (family trip or kid item) with real cost + date, accepts/edits the AI weight plan, logs saves, approves or rejects (with nudge) submissions, optionally adds makeup chores, manages Goal Album |
| **Kid** | Sees Today's chores with cadences and weights, marks done (photo when required), watches the percent bar, retries rejected chores |

Demo family is seeded: `parent@demo` / `kid@demo`, in-app **role switch** between them (one session, no slow re-login - the demo video depends on it).

## Screens

- **Parent:** Home (cost, save cadence, saved-so-far, kid %, makeup affordance) · New Goal (mode, cost, date, makeup switch + AI Suggest) · Approval inbox (% credits) · Goal Album
- **Kid:** Today (includes rejected-with-nudge and makeup items) · **percent-only** goal bar · Mark done (+ camera when required)

## Data (Supabase, RLS by `family_id`)

`families`, `profiles` (parent|kid), `goals` (`goal_mode`, cost, `allow_makeup`, `kid_id`), `chores` (`cadence` once|daily|weekly, `weight_pct`, `is_makeup`, `is_bonus`), `chore_submissions` (pending|approved|rejected + nudge), `parent_save_entries` (parent's offline money log), `ai_plans`, `album_items` (deletable). Storage paths prefixed by `family_id`.

## AI moments

1. **Suggest plan** - goal title/cost/date/kid age -> weekly parent save + 4-8 weighted chores summing to at least 100% + **why-this-plan in plain parent language**. Deterministic fallback when no LLM key.
2. **Photo assist** - for visually verifiable chores only ("made the bed" yes, "read a chapter" no); suggests approve/reject. **Parent is always final.**

## Non-goals (locked)

- Real cards / KYC / bank rails / in-app cash-out - the planner is in-app only; parents settle real money offline
- Dollars on kid screens - kid UI is percent only (rev 3 rule)
- Pocket / overshoot-to-pocket as a progress story (retired from rev 2)
- ReadyPup / Care Ladder code reuse - no vendor code
- App Store submission, multi-tenant billing
- Unsupervised AI auto-approve or auto-pay
- COPPA-style verifiable parental consent flows - demo photos and kid accounts are **test data only**

## Success

Parent-led 1-3 min video shows the full loop: AI weight plan -> assign -> kid done (with and without photo) -> approve / reject+redo -> percent bar fills -> parent save log -> album add/delete. Public repo with these docs. No banking or kids-privacy compliance claims anywhere in the copy.
