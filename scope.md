# Do My Chore — Scope

> Hackathon: [Build With AI: Basics](https://learn-ai-basics.devpost.com/) · Authoritative design: [`docs/superpowers/specs/2026-09-27-do-my-chore-design.md`](docs/superpowers/specs/2026-09-27-do-my-chore-design.md) (rev 2)

## Problem

Families want kids to earn toward **real goals** — Disneyland, camping, a game — not just receive a vague weekly allowance. Parents need a **plan to save** (cost, weeks, chore budget, top-ups). Kids need clear chores and visible progress.

## One-liner

Parent sets a goal and save plan; kids do chores (with photo proof when required); earnings split into **goal bank vs pocket**; chore photos become a deletable **Goal Album**.

## Users

| User | What they do |
|---|---|
| **Parent** | Creates goal + target date, accepts/edits AI save plan, approves or rejects (with nudge) chore submissions, manages Goal Album |
| **Kid** | Sees Today's chores, marks done (photo when required), sees goal vs pocket progress, retries rejected chores |

Demo family is seeded: `parent@demo` / `kid@demo`, in-app **role switch** between them (one session, no slow re-login — the demo video depends on it).

## Screens

- **Parent:** Home · New Goal (+ AI Suggest plan) · Goal detail (progress, weeks-to-goal) · Approval inbox · Goal Album
- **Kid:** Today (includes rejected-with-nudge items) · Goal progress (goal vs pocket) · Mark done (+ camera when required)

## Data (Supabase, RLS by `family_id`)

`families`, `profiles` (parent|kid), `goals`, `chores` (`requires_photo`), `chore_submissions` (pending|approved|rejected + nudge), `ledger_entries` (**money source of truth**, balances summed on read), `ai_plans`, `album_items` (deletable). Storage paths prefixed by `family_id`.

## AI moments

1. **Suggest plan** — goal title/amount/date/kid age → weekly top-up + 4–8 chores + **why-this-plan in plain parent language** (no ML jargon). Deterministic fallback when no LLM key.
2. **Photo assist** — for visually verifiable chores only ("cleaned the table" yes, "read a chapter" no); suggests approve/reject. **Parent is always final.**

## Non-goals (locked)

- Real cards / KYC / bank rails / in-app cash-out — the ledger is in-app only; parents settle real money offline
- ReadyPup / Care Ladder code reuse — new empty repo, no vendor code
- App Store submission, multi-tenant billing
- Unsupervised AI auto-approve or auto-pay
- COPPA-style verifiable parental consent flows — demo photos and kid accounts are **test data only**

## Success

Parent-led 1–3 min video shows the full loop: AI plan → assign → kid done (with and without photo) → approve / reject+redo → bars fill with overshoot-to-pocket → album add/delete. Public repo with these docs. No banking or kids-privacy compliance claims anywhere in the copy.
