# Do My Chore — Money & habit model (rev 3)

**Date:** 2026-09-27  
**Status:** Locked for implement (Anoop approved direction; makeup toggle added 2026-09-27)  
**Hackathon:** Build With AI: Basics — still a submission artifact, not a portfolio bet  
**Replaces:** dollar-reward / 80-20 pocket framing for *progress* (rev 2)

## 1. Intent (locked)

Two parallel accountabilities, one goal:

1. **Kid path (habit):** Chores build family-helpful habits. The goal incentivizes the habit; the kid must earn **100% of the goal** through chore progress (not a partial “kid share” of the dollars).
2. **Parent path (promise):** The app is a **financial planner** for the real cost (Disneyland family trip vs skateboard). Parent sees dollars and a save cadence so they do not break the bargain when the kid hits 100%.

Kid UI shows **% complete** only. Parent UI shows **money + %** (and realism checks).

## 2. Goal types

| Mode | Example | Parent planner focus |
| --- | --- | --- |
| `family_trip` | Disneyland (~USD 2.5k–5k; lower if local / no hotel) | Total trip cost, who goes, weekly/monthly parent save |
| `kid_item` | Skateboard (~USD 200 high end) | Item cost, parent save until kid hits 100% |

Both modes: kid still must reach **100% chore progress** to “earn” the goal. Money is what the parent must actually fund offline.

## 3. Chore progress math (kid earns 100%)

Each chore has:

- `cadence`: `once` | `daily` | `weekly`
- `weight_pct`: contribution toward the goal when the plan’s expected instances are completed
- `is_makeup`: boolean (default false). Makeup chores are parent-added catch-up tasks (see §3.1).
- Parent may set **one** chore at 100% (e.g. “A+ in AP Chem”, `once`)
- Parent may set many chores; **weights should sum to ≥ 100%**
  - Sum == 100%: every planned instance is needed
  - Sum **> 100%** (**oversubscribe / extra points**): kid can skip some chores and still hit 100%. Parent chooses this deliberately.

### Expected instances until `target_date`

Let `N` = weeks remaining (ceil days/7, minimum 1). POC uses `7*N` for daily (not calendar-day count).

| Cadence | Expected instances |
| --- | --- |
| `once` | 1 |
| `weekly` | `N` |
| `daily` | `7 * N` |

### Credit per approval

```
instance_credit_pct = weight_pct / expected_instances
```

Approve → add `instance_credit_pct` to chore progress (kid display caps at 100%; excess only on parent as “extra credit” when oversubscribed).

**Once** chore: one approval → full `weight_pct`.

Kid progress bar = `min(100, sum of approved instance credits)`.

No dollar amounts on kid screens.

### 3.1 Makeup chores (parent choice — small push)

- Goal flag: `allow_makeup` boolean, **default false**.
- When **off**: kid can only work the original plan (+ oversubscribe slack if parent set weights > 100%). No catch-up chores.
- When **on** and kid is **behind pace** (projected finish % at `target_date` < 100% given current progress vs elapsed expected instances):
  - Parent home shows a soft card: “Behind pace — add a makeup chore?”
  - Parent can add one or more `once` chores with `is_makeup = true` and a `weight_pct` that covers (part of) the gap.
  - Kid then sees those makeup chores on Today like any other chore; credit math is the same (`once` → full weight on one approval).
- Makeup is **never automatic**. Parent must opt in on the goal and explicitly add (or accept a suggested) makeup chore. That is the small push: option exists, not a bailout by default.
- Weight of makeup chores counts toward the same 100% bar (can push total assigned weights above 100% intentionally for catch-up).

## 4. Parent financial planner

Inputs: goal type (`family_trip` | `kid_item`), total cost, target date, `allow_makeup`, optional notes.

Outputs (parent only):

- Total to fund
- Suggested save: per day / week / month until target (total ÷ periods)
- Reality banner if weekly save is high (POC: warn only, never block)
- Parallel card: **Kid chore progress %**, weight list, oversubscribe headroom, behind-pace + makeup affordance when enabled
- Honesty copy: in-app planner only; parent settles money offline; no bank/card

Parent “keeping the bargain” = save tracker via `parent_save_entries` (manual “I saved this week” log). Not a bank link. Separate from kid % progress.

## 5. What we drop / change from rev 2

- Per-chore `reward_amount` and 80/20 goal/pocket split are **no longer the progress model**
- Pocket / overshoot-to-pocket **out of progress spine** for rev 3 POC (may remain as optional parent-facing allowance later; do not show on kid UI)
- Approve RPC stops writing `goal_credit` / `pocket_credit` from chore rewards; approvals only flip submission status (progress is derived from approved submissions × instance credits)
- Parent money path uses `parent_save_entries` (and optionally keep `parent_topup` ledger kind renamed in UI to “logged save”)
- AI Suggest plan: propose cadence + weights summing to ~100% (or slightly over for slack), parent save schedule for the cost, and respect `allow_makeup` (do not auto-add makeup chores in the initial plan)

## 6. Worked examples (locked)

### Disneyland (`family_trip`)

- Cost **$3,500**, **14 weeks** → parent ~**$250 / week**
- Kid weights 40% daily bed + 30% daily dishes + 20% weekly laundry + 10% once itinerary = 100%
- Optional oversubscribe to 130%; optional `allow_makeup` if behind later

### Skateboard (`kid_item`)

- Cost **$180**, **6 weeks** → parent **$30 / week**
- Kid: 50% daily shoes + 30% weekly trash + 20% weekly board wash, or one `once` at 100%

## 7. Demo spine (updated)

1. Parent creates Disneyland family trip, cost ~$3500, ~14 weeks, `allow_makeup` off by default → planner shows weekly save
2. AI / parent sets weighted chores summing to 100%
3. Role switch → kid sees Today + **% to goal** (no $)
4. Approvals advance % by instance credits
5. Parent home: kid % vs parent save checklist
6. (Optional beat) Flip `allow_makeup`, show behind-pace card, add one makeup once-chore, kid completes it

## 8. Non-goals

COPPA out of POC; no real payments; Final Submit only with Anoop; no calendar-day daily formula change unless Anoop asks later.

## 9. Open polish (non-blocking)

- Soft realism thresholds for save warnings
- Whether parent “extra credit” overflow UI is shown beyond a single line

## 10. Stretch goals (hackathon — after MVP)

Not required for demo video or Final Submit. Build only if MVP %/planner/makeup is green.

### 10.1 Multi-kid household

- **One kid per goal** (locked). Sibling goals do not share a progress bar.
- `goals.kid_id` (required when multi-kid is on); `chores.kid_id` matches the goal’s kid.
- Parent home: group or label goals by kid display name + %.
- Approvals inbox: show kid name on each card.
- Seed stretch: second kid profile + second small goal (optional; do not break single-kid demo login).

### 10.2 Swap chores

- Kid A requests swap of their open chore instance with Kid B’s (same family).
- Parent confirms (default for stretch) or auto-accept if parent setting allows.
- Swap exchanges assignment for that instance / chore row; weights stay with the chore definition (or follow the chore id — implement as chore_id ownership swap so weight math unchanged).
- Rejected swap: both kids keep original chores; nudge optional.

### 10.3 Bonus chores (kid-proposed, anti-game weights)

- Kid can **propose** a bonus chore (title + optional photo requirement + suggested cadence `once` default).
- Parent **accepts or rejects**. Parent does **not** type the weight.
- On accept, app **randomizes `weight_pct`** in a parent-visible band (POC suggest: uniform 3–12%, or discrete slots {3,5,8,10,12}) and stores it; show the roll to parent (“Weight landed at 8%”) so kids cannot lobby for a fat %.
- Bonus chores are `is_bonus = true` (distinct from `is_makeup`). They add to the kid’s weight pool (can oversubscribe).
- Rejected proposals: kid sees nudge; can repropose a different title later.
