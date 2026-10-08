# Do My Chore Money Model Rev 3: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace dollar-reward / pocket progress with kid % progress (weighted once/daily/weekly chores) plus a parent-only dollar save planner, including optional makeup chores; keep Flutter + Supabase demo filmable.

**Architecture:** Progress is derived from approved `chore_submissions` × per-chore `instance_credit_pct` (weight ÷ expected instances). Parent money is a separate `parent_save_entries` log against `goals.target_amount`. Approve RPC stops minting goal/pocket ledger credits from chore rewards. Kid UI never shows dollars.

**Tech Stack:** Existing Flutter app under `app/`, Supabase migrations + seed + `suggest-plan` edge function, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md` (locked). Stretch (§10 multi-kid, swap, bonus) is Tasks S1-S3 only after MVP Tasks 1-8 pass.

## Global Constraints

- Spec rev 3 is authoritative for progress; rev 2 design dollars-on-kid is retired for UI
- Kid screens: **% only** (no `$`, no pocket)
- Parent screens: cost + save plan + kid %
- `allow_makeup` default **false**; makeup never auto-added
- Daily expected instances = `7 * N` weeks (POC); once=1; weekly=N
- Weights may sum > 100% (oversubscribe); kid bar caps at 100%
- No em dashes in user-facing copy
- TDD: failing test → implement → pass → commit per task
- Demo accounts stay `parent@demo` / `kid@demo` / `demo1234`
- Final Submit only with Anoop; stretch not required for submit

## File structure (touch)

```
supabase/migrations/20260927200000_rev3_money_model.sql   # NEW
supabase/seed.sql                                          # rewrite goal/chores
supabase/functions/suggest-plan/index.ts                   # weights not rewards
app/lib/services/chore_progress_math.dart                  # NEW pure math
app/lib/services/ledger_math.dart                          # parent save helpers; drop overshoot-as-progress
app/lib/services/chore_service.dart
app/lib/services/goal_service.dart
app/lib/services/ai_service.dart
app/lib/services/queries.dart
app/lib/features/parent/{home,new_goal,approvals}_screen.dart
app/lib/features/kid/{today,mark_done}_screen.dart
app/test/chore_progress_math_test.dart                     # NEW
app/test/ledger_math_test.dart                             # retarget
app/test/overshoot_test.dart                               # retire or replace
app/test/plan_validation_test.dart
docs/demo-video-script.md
docs/devpost-draft.md
```

---

### Task 1: Pure chore progress math + tests

**Files:**
- Create: `app/lib/services/chore_progress_math.dart`
- Create: `app/test/chore_progress_math_test.dart`

**Interfaces:**
- Produces:
  - `int weeksRemaining({required DateTime today, required DateTime targetDate})`
  - `int expectedInstances({required String cadence, required int weeksN})` // once→1, weekly→N, daily→7*N; N>=1
  - `double instanceCreditPct({required double weightPct, required int expectedInstances})`
  - `double kidProgressPct({required List<({double weightPct, String cadence, int approvedCount})> chores, required int weeksN})` // sum credits, cap 100
  - `bool isBehindPace({required double progressPct, required int weeksN, required int weeksElapsed, required double planWeightSum})` // simple: expectedPace = 100 * weeksElapsed/weeksN (clamp); behind if progressPct + 1e-6 < expectedPace && allow path
  - `double randomBonusWeightPct(Random rng)` // stretch helper OK to add empty stub returning discrete 3|5|8|10|12

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/chore_progress_math.dart';

void main() {
  test('daily credit is weight / (7*N)', () {
    expect(instanceCreditPct(weightPct: 40, expectedInstances: 98), closeTo(40 / 98, 1e-9));
  });

  test('once credit is full weight', () {
    expect(instanceCreditPct(weightPct: 10, expectedInstances: 1), 10);
  });

  test('Disneyland perfect streak hits 100', () {
    final n = 14;
    final chores = [
      (weightPct: 40.0, cadence: 'daily', approvedCount: 7 * n),
      (weightPct: 30.0, cadence: 'daily', approvedCount: 7 * n),
      (weightPct: 20.0, cadence: 'weekly', approvedCount: n),
      (weightPct: 10.0, cadence: 'once', approvedCount: 1),
    ];
    expect(kidProgressPct(chores: chores, weeksN: n), 100);
  });

  test('kid bar caps at 100 when oversubscribed', () {
    final n = 6;
    final chores = [
      (weightPct: 80.0, cadence: 'once', approvedCount: 1),
      (weightPct: 50.0, cadence: 'once', approvedCount: 1),
    ];
    expect(kidProgressPct(chores: chores, weeksN: n), 100);
  });
}
```

- [ ] **Step 2: Run tests, expect FAIL** (library missing)

Run: `cd app && flutter test test/chore_progress_math_test.dart`

- [ ] **Step 3: Implement `chore_progress_math.dart`** to match tests (no Flutter UI imports).

- [ ] **Step 4: Run tests, expect PASS**

- [ ] **Step 5: Commit** `feat(rev3): chore progress math (% weights, cadences)`

---

### Task 2: Schema migration rev 3

**Files:**
- Create: `supabase/migrations/20260927200000_rev3_money_model.sql`
- Modify: approve function behavior (same file)

**Interfaces:**
- `goals`: add `goal_mode text not null default 'kid_item' check (goal_mode in ('family_trip','kid_item'))`, `allow_makeup boolean not null default false`, keep `target_amount` as parent cost
- `chores`: add `cadence text not null default 'once' check (cadence in ('once','daily','weekly'))`, `weight_pct numeric(6,2) not null check (weight_pct > 0)`, `is_makeup boolean not null default false`, `is_bonus boolean not null default false`; drop dependence on `reward_amount` / `default_split_goal_pct` for progress (columns may remain nullable for one migration then dropped, or set unused, **prefer drop** after backfill)
- `parent_save_entries` new table: `id, family_id, goal_id, amount, note, created_by, created_at` with RLS parent insert / family read
- Replace `approve_chore_submission`: parent-only; set submission approved; **do not** insert goal_credit/pocket_credit from rewards
- Stretch columns deferred to Task S1 (`goals.kid_id`, `chores.kid_id`) unless cheap to add nullable now, **add nullable `kid_id` on goals/chores now** pointing at profiles for forward compat; seed fills demo kid

- [ ] **Step 1: Write migration SQL** altering tables, creating `parent_save_entries`, replacing approve fn, updating RLS.

- [ ] **Step 2: Apply locally** `supabase db reset` (demo machine) and confirm no errors.

- [ ] **Step 3: Commit** `feat(rev3): schema for % weights, makeup, parent saves`

---

### Task 3: Seed Disneyland % plan

**Files:**
- Modify: `supabase/seed.sql`

- [ ] **Step 1: Rewrite goal** to Disneyland `family_trip`, `target_amount` 3500, `target_date` ~14 weeks out, `allow_makeup` false, `kid_id` = demo kid.

- [ ] **Step 2: Chores** match worked example (bed daily 40, dishes daily 30, laundry weekly 20, itinerary once 10); drop old reward rows.

- [ ] **Step 3: AI plan JSON** stores weights + `weekly_parent_save` (~250) + why in plain language; no chore dollar rewards.

- [ ] **Step 4: `supabase db reset`** smoke; commit `chore(rev3): seed Disneyland % plan`

---

### Task 4: Dart models/services, progress + parent saves

**Files:**
- Modify: `app/lib/services/queries.dart`, `goal_service.dart`, `chore_service.dart`
- Modify: `app/lib/services/ledger_math.dart`, add `suggestedSavePerWeek({cost, weeksN})`, `parentSaveProgress`; keep or gut pocket helpers unused by UI
- Modify tests: replace overshoot-as-progress tests; keep parent save math tests

**Interfaces:**
- `GoalProgressView`: `choreProgressPct`, `parentSaved`, `targetAmount`, `allowMakeup`, `goalMode`, `behindPace` (parent only fields ok on shared view but kid UI ignores money)
- `approve` calls RPC that only flips status
- `logParentSave(goalId, amount)`
- `addMakeupChore(goalId, title, weightPct)` only if `allow_makeup`

- [ ] **Step 1: Failing service/unit tests** for progress aggregation from fake approved counts.

- [ ] **Step 2: Implement service changes.**

- [ ] **Step 3: `flutter test`** green for touched tests.

- [ ] **Step 4: Commit** `feat(rev3): services use % progress + parent saves`

---

### Task 5: AI suggest plan → weights

**Files:**
- Modify: `app/lib/services/ai_service.dart`, `goal_service.dart` validatePlan, `supabase/functions/suggest-plan/index.ts`, `app/test/plan_validation_test.dart`

**Interfaces:**
- `ChoreSpec`: `title`, `cadence`, `weightPct`, `requiresPhoto`, `isMakeup` default false (no `reward`)
- `AiPlanSuggestion`: `weeklyParentSave`, `chores`, `why`
- `validatePlan`: weights sum >= 100 and each weight > 0; cadences valid

- [ ] **Step 1: Update deterministic catalog** to Disneyland-like weights summing to 100.

- [ ] **Step 2: Edge function** returns same shape; fallback deterministic.

- [ ] **Step 3: Tests + commit** `feat(rev3): AI plan suggests cadence weights`

---

### Task 6: Parent UI

**Files:**
- Modify: `app/lib/features/parent/home_screen.dart`, `new_goal_screen.dart`, `approvals_screen.dart`

- [ ] **Step 1: New goal**, mode, cost, date, `allow_makeup` switch, then accept AI weight plan.

- [ ] **Step 2: Home**, show parent saved / cost, suggested weekly save, kid %, behind-pace card if `allow_makeup && behindPace` with “Add makeup chore” action.

- [ ] **Step 3: Approvals**, show chore title + credit % preview, not `$reward`.

- [ ] **Step 4: Manual widget smoke / commit** `feat(rev3): parent planner + makeup affordance`

---

### Task 7: Kid UI (% only)

**Files:**
- Modify: `app/lib/features/kid/today_screen.dart`, `mark_done_screen.dart`

- [ ] **Step 1: Remove** dollar and pocket lines; show `Goal 47%` style bar.

- [ ] **Step 2: Today list** includes makeup/bonus chores when present; cadence label optional.

- [ ] **Step 3: Commit** `feat(rev3): kid UI shows % only`

---

### Task 8: Docs + demo script

**Files:**
- Modify: `docs/demo-video-script.md`, `docs/devpost-draft.md`, README honesty line if needed

- [ ] **Step 1: Script beats** match §7 of spec (no $500 kid bank).

- [ ] **Step 2: Devpost** mentions habit % + parent planner (AI suggest weights).

- [ ] **Step 3: Commit** `docs(rev3): demo + Devpost for % model`

---

## Stretch (after Task 8)

### Task S1: Multi-kid

- Second profile in seed optional; require `kid_id` on goals/chores; parent home labels by kid; still one kid login for primary demo path OR add `kid2@demo`.

### Task S2: Swap chores

- Table `chore_swap_requests`; kid propose; parent confirm; swap `chores.kid_id` or instance assignment.

### Task S3: Bonus chores (randomized weight)

- Kid propose → parent accept/reject → on accept `weight_pct = randomBonusWeightPct(secureRandom)` in {3,5,8,10,12}; show roll to parent; `is_bonus=true`.

---

## Self-review

- Spec §1-§7 + makeup §3.1 → Tasks 1-8
- Stretch §10 → S1-S3
- No placeholders; approve no longer dollars
