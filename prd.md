# Do My Chore — PRD

> Hackathon: Build With AI: Basics · Rev 3 money model is authoritative: [`docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md`](docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md)

## Personas

- **Parent (Priya):** wants to fund the Disneyland trip without a scramble and keep her son honest about habits; approves chores in under a minute a day.
- **Kid (Arjun, 9):** wants to see the percent bar move every time he finishes a chore; dollars are not his job.

## User stories & acceptance criteria

### Parent

| # | Story | Acceptance |
|---|---|---|
| P1 | As a parent I create a goal with a type, cost, and target date | New Goal form writes a `goals` row with `goal_mode`, cost > 0, date, `allow_makeup` (default off) |
| P2 | As a parent I get an AI-suggested plan I can edit before accepting | Suggest returns weekly parent save + 4-8 chores with cadence + weight, weights summing to at least 100%, plus a plain-language "why"; Accept writes `chores` + accepted `ai_plans` |
| P3 | As a parent I approve or reject submissions | Approve flips the submission status; progress advances by instance credit; Reject stores a nudge and returns the chore to Kid Today |
| P4 | As a parent I see the money plan | Home shows cost, suggested weekly save (cost / weeks), saved-so-far from `parent_save_entries`, and the kid percent |
| P5 | As a parent I log my saves | "I saved this week" appends to `parent_save_entries`; only parents can write |
| P6 | As a parent I can add makeup chores | Only when `allow_makeup` is on: parent adds one-time `is_makeup` chores that count toward the same 100% bar; never automatic |
| P7 | As a parent I manage the Goal Album | Photos from approved submissions can be added; any album item can be deleted |
| P8 | As a parent I trust the money story | App states the planner is not real money; parents settle offline |

### Kid

| # | Story | Acceptance |
|---|---|---|
| K1 | As a kid I see Today's chores | Includes cadence labels, weights, rejected-with-nudge retries, and makeup chores when present |
| K2 | As a kid I mark a chore done | If `requires_photo`, submit is blocked without a photo |
| K3 | As a kid I see my progress in percent | Bar = sum of approved instance credits, capped at 100%; **no dollar amounts anywhere on kid screens** |
| K4 | As a kid I retry rejected chores | Resubmission creates a **new** submission row |

### Demo spine (parent-led, 1-3 min)

Role switch -> New Goal (mode/cost/date/makeup) -> Suggest plan (show the "why" and weights) -> Accept -> Kid Today -> mark done with photo -> Parent approve (% credit) -> parent logs a save -> Album add/delete. Optional beat: makeup chore.

## Constraints (locked)

1. **Kid UI = percent only.** No dollars, no pocket on any kid surface.
2. **Parent = planner.** Cost + save cadence + saved-so-far; offline settlement; no bank/card claims.
3. **Weights may oversubscribe.** Sum > 100% is a deliberate slack; the kid bar caps at 100%.
4. **Instance credit:** weight / expected instances (once=1, weekly=N, daily=7*N).
5. **Makeup:** `allow_makeup` default false; parent-added only; never automatic.
6. **RLS everywhere:** every family-scoped table restricted by `family_id`; storage paths prefixed by `family_id`.
7. **Photo only where visible:** `requires_photo` only on visually verifiable chores; parent always final.
8. **Fallbacks:** both AI moments work with zero API keys.
9. **Honest copy:** no banking, KYC, COPPA, or verification-accuracy claims. No em dashes in user-facing copy.
10. **Demo UX:** in-app Parent <-> Kid role switch; no login friction in the video.

## Metrics for the hack

- Full demo loop filmable without cuts or login waits
- All automated tests green (progress math, validation, fallbacks, role switch)
- RLS verified: kid session cannot read another family's rows
- Kid screens verified free of dollar figures
