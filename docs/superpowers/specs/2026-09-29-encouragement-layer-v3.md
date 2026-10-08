# Do My Chore: Encouragement layer (V3)

**Date:** 2026-09-29  
**Status:** Locked for implement (Anoop approved direction; nits applied this date)  
**Sits on:** rev-3 money model (`docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md`)  
**Hackathon:** Build With AI: Basics, still a submission artifact; Basics demo video remains on hold separately  
**Mockup:** V3 HTML deck (encouragement layer). Where mockup copy conflicts with nits below, **nits win**.

## 1. Problem

Rev 3 shipped the money split (kid = % only, parent = $ planner). The kid path still talks like a gradebook: **TRY AGAIN**, **PARENT SAID**, “Try again with a clearer photo…”, “Keep the habits going. 100% earns the trip.” Rejection reads as failure. A slow week has no path forward except parent-side “Behind pace.” Finishing a day or hitting 100% has no calm moment.

V3 is an **emotional feedback layer only**. It does not change weights, credits, or parent money.

## 2. Locked decisions (nits applied)

### 2.1 Rejection → next try, never failure

- Kid badge: **NEXT TRY** (never TRY AGAIN / rejected).
- Kid note eyebrow: **A note from your parent** (never PARENT SAID).
- Today row shows the stored nudge as a warm marigold note. Do not prefix “Try again -”.
- Parent Approvals: rename **Reject with nudge** → **Send back**.
- **Send back** opens a bottom sheet: editable note + **live preview of exactly what the kid will read** (eyebrow + quote, same type/color as Mark Done). Confirm calls existing `rejectNudge` then `rejectSubmission` (writes `status: rejected` + `reject_nudge`). Rejected rows never flip back to pending; retry inserts a new submission.
- Default nudge (when the parent does not edit): kind, specific, photo-tip. **Not** “Try again with a clearer photo of the finished …”. Locked default:

  > So close! One more photo of the whole "{chore title}" - bright light if you can - and this one's done.

- Empty sheet text falls back to that default. Do not persist a blank `reject_nudge`.

### 2.2 Celebration

- **Day complete** (every Today chore is `sent` for this period, see §4): card “That's today done.” + soft confetti (skip when `MediaQuery.disableAnimations`) + chip “+{X}% moved the bar today” + calm copy that the parent still has to look. **Pending rows stay on the list** as “Sent - waiting for your parent”. They do not vanish.
- `{X}` is the sum of existing `instanceCreditPct` for chores whose latest submission was created today. The HTML mock’s “+5.7%” is illustrative only; shipped math is the same per-check-in % already shown on Mark Done / Approvals (demo bed at 14 weeks is ~+0.4%, not 5.7).
- **Mark Done after send:** do not `pop` immediately. Show “Sent to your parent.” / “The bar moves the moment they take a look.” then **Back to today**.
- **Goal at 100%:** full-screen finale. Reuse the existing Today hero image (`assets/photos/castle.jpg`, no goal cover column exists). Headline “You earned it.” Hand-off: parent takes it from here / talk about the trip (or the reward) together. **No dollars** on kid screens.

### 2.3 Soft pace (path, not debt)

- Show the cream pace card only when `GoalProgressView.kidBehindPace` is true (existing `isBehindPace` in `chore_progress_math.dart`: linear projection of approved % vs `weeksElapsed` / `weeksN`). Do not invent a second pace formula. Designer-only chips such as **Slow week** do **not** ship.
- Hero under the rail when slow:

  > Every check-in moves it. The trip stays put.

  For `kid_item`, swap “trip” → “reward”.
- Pace card is **path only**. Title names the computed check-in count (greedy: how many open instance credits close the pace gap). Body names the open chores. Locked direction (demo: bed + dishes):

  > Two check-ins today puts the week back on pace.  
  > Bed and dishes are right there - each one moves the bar.

  Do **not** say “No catch-up pile, no lost ground.”
- **Open Today hero** (not slow, not earned): replace “Keep the habits going. 100% earns the trip.” with:

  > Every check-in moves the bar.

  The goal is never a carrot and never a threat.
- Pace card is hidden when the day is fully sent or the goal is already earned. Parent Home may keep its own “Behind pace” makeup card (parent-facing).

### 2.4 Copy rules (global, kid-visible)

- Never use: behind / missed / failed / overdue / rejected / try again (as failure).
- No em dashes in user-facing copy. No emoji.
- Kid UI stays **% only**. Parent planner stays dollars.

## 3. Non-goals

- No new Supabase table or column if `reject_nudge` stays sufficient (it is, see §5).
- No change to approve RPC, weights, instance credits, or parent save math.
- Do not touch Nebius / token-factory three-beat work (`feat/nebius-token-factory`, PR #3).
- Do not merge until Anoop greenlights. Do not revive the Basics demo video in this slice.
- Do not ship mockup state chips, Slow week chrome, or any designer-only control.
- Do not rename the parent Approvals **load-error** button “Try again” (network retry, not a chore rejection).
- Makeup / bonus / stretch (multi-kid, swap) unchanged.

## 4. Today row states (reuse existing submissions)

`todayForKid` already selects `chore_submissions(status, reject_nudge, created_at)` but only surfaces a reject nudge. V3 must expose latest status + timestamp. No schema change.

| Latest submission | Cadence rule | Kid row |
| --- | --- | --- |
| none | n/a | **open** (tappable) |
| `rejected` | any | **next try** (tappable, badge + note) |
| `pending` | any | **sent** (not tappable) |
| `approved` | `once` | **sent** (complete for the goal) |
| `approved` | `daily` | **sent** if `created_at` is today, else **open** |
| `approved` | `weekly` | **sent** if same ISO week as `created_at`, else **open** |

**All submitted for today** = every listed chore is `sent` (none `open`, none `next try`).

## 5. Schema / API (verified, do not invent)

- `chore_submissions.reject_nudge text` already exists (`supabase/migrations/20260927000000_init.sql`).
- `rejectNudge({required String choreTitle, String? parentNote})` already prefers a non-empty parent note; default string is what changes.
- `rejectSubmission(id, nudge)` already writes `status: rejected` + `reject_nudge` + `decided_at`. `kAllowedTransitions` has no `rejected → pending`.
- Pace: `isBehindPace` / `GoalProgressView.kidBehindPace` / `weeksElapsed` from `goals.created_at`.
- Goal finale image: no cover column; reuse `assets/photos/castle.jpg` (same as Today / Parent Home).

**Schema gap:** none. `reject_nudge` is enough.

## 6. Acceptance criteria

1. Parent taps **Send back**, edits the note, sees a live kid preview, confirms; kid Today shows **NEXT TRY** + “A note from your parent” with that text; Mark Done uses the same eyebrow. Default note has no “try again”.
2. After the kid sends a chore, Mark Done shows the sent confirmation (not an instant pop). Today keeps the row as “Sent - waiting for your parent”.
3. When every Today chore is sent, the day-done card + chip + (motion-safe) confetti appear; pending rows remain.
4. When `kidBehindPace` and at least one chore is open, the cream pace card and slow hero line appear; copy is path-only; no Slow week chip.
5. Open (on-pace) hero is “Every check-in moves the bar.” Never “100% earns the trip.”
6. At 100% approved progress, the kid sees the full-screen finale; no `$` on that screen.
7. Grep of kid-visible strings finds none of the banned words. `flutter test` green. Integration walkthrough updated (**Send back**, **NEXT TRY**).
8. Implementation PR stays off the Nebius branch; merge waits for Anoop.

## 7. Code anchors (current main)

- `app/lib/features/parent/approvals_screen.dart`, `_reject` uses default `rejectNudge` then `rejectSubmission`; button still “Reject with nudge”; no sheet.
- `app/lib/services/chore_service.dart`, `rejectNudge`, `rejectSubmission`.
- `app/lib/features/kid/today_screen.dart`, “Try again - …”, badge **TRY AGAIN**, hero “Keep the habits going. 100% earns the trip.”
- `app/lib/features/kid/mark_done_screen.dart`, “PARENT SAID”; `Navigator.pop` on successful send.
- `app/lib/core/dmc_theme.dart`, Ledger tokens (porcelain / pine / marigold).
- `app/lib/services/chore_progress_math.dart`, `app/lib/services/queries.dart`, % credit and pace.
- `app/test/overshoot_test.dart`, asserts default nudge contains “try again” (must retarget).
- `app/integration_test/demo_walkthrough_test.dart`, finds “Reject with nudge” and “Try again”.
