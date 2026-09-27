# Do My Chore — PRD

> Hackathon: Build With AI: Basics · Design rev 2 is authoritative: [`docs/superpowers/specs/2026-09-27-do-my-chore-design.md`](docs/superpowers/specs/2026-09-27-do-my-chore-design.md)

## Personas

- **Parent (Priya):** wants her kid to save for Disneyland with a realistic plan she controls; approves chores in under a minute a day.
- **Kid (Arjun, 9):** wants to see the bar move toward Disneyland every time he finishes a chore; wants to know exactly what "done" means.

## User stories & acceptance criteria

### Parent

| # | Story | Acceptance |
|---|---|---|
| P1 | As a parent I create a goal with a cost and target date | New Goal form writes a `goals` row; target must be > 0 |
| P2 | As a parent I get an AI-suggested save plan I can edit before accepting | Suggest returns weekly top-up + 4–8 chores + plain-language "why"; I can edit every line; Accept writes `chores` + accepted `ai_plans` |
| P3 | As a parent I approve or reject submissions | Approve writes ledger entries in one transaction; Reject stores a nudge and returns the chore to Kid Today |
| P4 | As a parent I see weeks-to-goal and progress | Weeks card = max(1, ceil((target − goalBank) / weeklyTopup)) when topup > 0; progress caps at 100% |
| P5 | As a parent I manage the Goal Album | Photos from approved submissions can be added; any album item can be deleted |
| P6 | As a parent I trust the money story | App states the ledger is not real money; parents settle offline |

### Kid

| # | Story | Acceptance |
|---|---|---|
| K1 | As a kid I see Today's chores | Includes rejected-with-nudge chores flagged for retry |
| K2 | As a kid I mark a chore done | If `requires_photo`, submit is blocked without a photo |
| K3 | As a kid I see goal vs pocket | Balances come from ledger sums; overshoot fills the goal to target, remainder lands in pocket |
| K4 | As a kid I retry rejected chores | Resubmission creates a **new** submission row |

### Demo spine (parent-led, 1–3 min)

Role switch → New Goal → Suggest plan (show the "why") → Accept → Kid Today → mark done with photo → Parent approve → progress + overshoot-to-pocket if cued → Album add/delete.

## Constraints (locked)

1. **Ledger honesty:** `ledger_entries` is the only money source of truth; no denormalized balance column; overshoot splits goal/pocket inside one transaction.
2. **RLS everywhere:** every family-scoped table restricted by `family_id`; storage paths prefixed by `family_id`.
3. **Photo only where visible:** `requires_photo` only on visually verifiable chores; parent always final; AI never auto-pays.
4. **Fallbacks:** both AI moments work with zero API keys (deterministic plan builder; photo assist abstains with a clear reason).
5. **Honest copy:** no banking, KYC, COPPA, or verification-accuracy claims.
6. **Demo UX:** in-app Parent ↔ Kid role switch; no login friction in the video.

## Metrics for the hack

- Full demo loop filmable without cuts or login waits
- All automated tests green (ledger math, overshoot, fallbacks, role switch)
- RLS verified: kid session cannot read another family's rows
