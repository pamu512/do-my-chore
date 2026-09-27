# Do My Chore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Flutter + Supabase POC for Build With AI: Basics where a parent sets a kid goal, gets an AI save/chore plan, kids complete chores (photo when required), parent approves, ledger fills goal bank vs pocket (overshoot → pocket), and photos land in a deletable Goal Album.

**Architecture:** New empty public GitHub repo. Flutter app with Parent ↔ Kid role switch on a seeded demo family. Supabase provides Auth, Postgres (RLS by `family_id`), Storage for photos, and Edge Functions for Suggest Plan + Photo Assist (deterministic fallbacks when keys missing). `ledger_entries` is the money source of truth; balances are summed on read.

**Tech Stack:** Flutter 3.22+ (Dart 3), `supabase_flutter`, `flutter_riverpod` (or `provider`), `go_router`, `image_picker`, `cached_network_image`; Supabase (Postgres + Auth + Storage + Edge Functions on Deno); `dart_test` / `flutter_test`; Devpost Learn skill pack artifacts `scope.md`, `prd.md`, `spec.md`.

## Global Constraints

- Spec (authoritative): `docs/superpowers/specs/2026-09-27-do-my-chore-design.md` (rev 2)
- **Empty folder / new repo only** — no ReadyPup or Care Ladder code
- In-app ledger only; no banking/KYC/cards; copy says parent settles real money offline
- COPPA-style consent out of scope; demo photos are test data only
- `requires_photo` only for visually verifiable chores; parent always final on approve
- Overshoot: fill goal to `target_amount`, remainder → pocket in same transaction
- Rejected submission → chore back on Kid Today with nudge; new submission row on retry
- RLS on all family-scoped tables + storage paths prefixed by `family_id`
- AI “why this plan” in plain parent language; deterministic fallback if no LLM/vision key
- Hackathon artifact, not portfolio product bet; Care Ladder still higher priority unless bumped
- Demo UX: in-app role switch (prefer) or dual simulators; 1–3 min filmable loop
- TDD: failing test → implement → pass → commit per task

---

## File structure (create)

```
do-my-chore/                          # new GitHub repo root
  README.md
  LICENSE
  scope.md                            # from skill pack /onboard→/scope (or mirrored from design)
  prd.md
  spec.md
  docs/superpowers/specs/2026-09-27-do-my-chore-design.md
  docs/superpowers/plans/2026-09-27-do-my-chore.md
  supabase/
    config.toml
    migrations/20260927000000_init.sql
    seed.sql
    functions/suggest-plan/index.ts
    functions/photo-assist/index.ts
  app/                                # flutter create
    pubspec.yaml
    lib/
      main.dart
      app.dart
      core/supabase_client.dart
      core/theme.dart
      models/{family,profile,goal,chore,submission,ledger_entry,album_item,ai_plan}.dart
      services/{auth_service,goal_service,chore_service,ledger_service,album_service,ai_service}.dart
      providers/*.dart
      features/
        shell/role_switch_shell.dart
        parent/{home,new_goal,goal_detail,approvals,album}_screen.dart
        kid/{today,goal,mark_done}_screen.dart
      widgets/{progress_bar,chore_tile,approval_card}.dart
    test/
      ledger_math_test.dart
      overshoot_test.dart
      goal_service_test.dart
      widget_role_switch_test.dart
```

---

### Task 0: Repo bootstrap + skill-pack planning docs

**Files:**
- Create: repo root, `README.md`, `LICENSE` (MIT), copy design+plan into `docs/superpowers/...`
- Create: `scope.md`, `prd.md`, `spec.md` (content aligned to design; produced via Devpost Learn skill pack commands when Mac Hermes runs `/onboard`→`/scope`→`/prd`→`/spec`, or authored to match design if skills not installed yet — **must exist before Final Submit**)

**Interfaces:**
- Produces: public empty-origin repo URL; planning docs judges require

- [ ] **Step 1:** Create empty GitHub repo `pamu512/do-my-chore` (or Anoop-chosen name). Clone to empty folder. No vendor code.

- [ ] **Step 2:** Install skill pack in that folder: `npx skills add challengepost/learn-ai-basics --all -y` and run `/onboard` → `/scope` → `/prd` → `/spec` with Do My Chore design as the brief, **or** write `scope.md` / `prd.md` / `spec.md` that cover problem, users, screens, data, AI, non-goals from the design (same substance).

- [ ] **Step 3:** Add README: one-liner, how to run Flutter + Supabase, demo parent/kid role switch, money-honesty + demo-photo privacy notices.

- [ ] **Step 4:** Commit

```bash
git add README.md LICENSE scope.md prd.md spec.md docs/
git commit -m "docs: Do My Chore Basics planning docs and design"
```

---

### Task 1: Supabase schema + RLS + seed

**Files:**
- Create: `supabase/migrations/20260927000000_init.sql`, `supabase/seed.sql`

**Interfaces:**
- Produces: tables `families`, `profiles`, `goals`, `chores`, `chore_submissions`, `ledger_entries`, `ai_plans`, `album_items`; RLS policies; seed family with parent+kid auth users

- [ ] **Step 1: Write migration SQL** including:

```sql
-- goals: no authoritative balance column
create table goals (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references families(id),
  title text not null,
  target_amount numeric(12,2) not null check (target_amount > 0),
  target_date date,
  status text not null default 'active',
  created_at timestamptz default now()
);
-- chores.requires_photo boolean not null default false
-- ledger_entries: kind in ('goal_credit','pocket_credit','parent_topup')
-- album_items deletable (plain delete policy for parent)
-- RLS: auth.uid() → profiles.family_id match
```

- [ ] **Step 2: Seed** demo family, `parent@demo` / `kid@demo` (document passwords in README as demo-only), one goal “Disneyland”, mix of chores with and without `requires_photo`.

- [ ] **Step 3: Apply locally** `supabase db reset` (or linked project). Verify RLS: kid cannot read other family.

- [ ] **Step 4: Commit** `feat(db): init schema RLS and demo seed`

---

### Task 2: Ledger math (pure Dart) — overshoot + balances

**Files:**
- Create: `app/lib/services/ledger_math.dart`
- Test: `app/test/ledger_math_test.dart`

**Interfaces:**
- Produces: `BalanceSummary sumLedger(List<LedgerEntry>)`; `({double goalCredit, double pocketCredit}) splitCredit({required double amount, required double goalBalance, required double targetAmount})`

- [ ] **Step 1: Failing tests**

```dart
test('overshoot fills goal then pocket', () {
  final r = splitCredit(amount: 30, goalBalance: 90, targetAmount: 100);
  expect(r.goalCredit, 10);
  expect(r.pocketCredit, 20);
});

test('under target all to goal when split 100%', () {
  final r = splitCredit(amount: 15, goalBalance: 0, targetAmount: 100);
  expect(r.goalCredit, 15);
  expect(r.pocketCredit, 0);
});
```

Also test `sumLedger` for goal vs pocket totals; progress capped at 1.0.

- [ ] **Step 2:** Run `flutter test test/ledger_math_test.dart` — expect FAIL

- [ ] **Step 3:** Implement `ledger_math.dart`

- [ ] **Step 4:** Tests PASS → commit `feat(ledger): overshoot and balance helpers`

---

### Task 3: Flutter app shell + Supabase client + role switch

**Files:**
- Create: Flutter project under `app/`, `lib/core/supabase_client.dart`, `lib/features/shell/role_switch_shell.dart`, theme, router

**Interfaces:**
- Produces: app boots; env via `--dart-define=SUPABASE_URL=...` and `SUPABASE_ANON_KEY=...`; AppBar action toggles Parent/Kid mode for demo family

- [ ] **Step 1:** `flutter create app --org com.pamu.domychore --project-name do_my_chore`

- [ ] **Step 2:** Wire `supabase_flutter` init; login helper for demo accounts **or** magic role switch that sets `activeProfileId` without full re-auth (document chosen approach in README).

- [ ] **Step 3:** Widget test: role switch shows Parent Home vs Kid Today scaffold.

- [ ] **Step 4:** Commit `feat(app): shell role switch and supabase init`

---

### Task 4: Goals + AI Suggest plan

**Files:**
- Create: `goal_service.dart`, `ai_service.dart`, `new_goal_screen.dart`, `goal_detail_screen.dart`
- Create: `supabase/functions/suggest-plan/index.ts`
- Test: unit test for deterministic fallback parser/builder in Dart mirroring edge fallback

**Interfaces:**
- Consumes: Supabase goals/chores/ai_plans
- Produces: `Future<AiPlanSuggestion> suggestPlan({title, targetAmount, targetDate, kidAge})`; `acceptPlan(goalId, suggestion)` writes chores (`requires_photo` only on visual ones)

- [ ] **Step 1:** Edge function returns JSON `{ weekly_topup, chores: [{title, reward, requires_photo, split_goal_pct}], why: string }`. If `OPENAI_API_KEY` (or chosen key) missing, deterministic builder from amount/weeks. Prompt insists **parent-language why**.

- [ ] **Step 2:** Flutter New Goal screen: form → Suggest plan → edit list → Accept.

- [ ] **Step 3:** Test deterministic fallback yields ≥4 chores and `why.isNotEmpty`.

- [ ] **Step 4:** Commit `feat: AI suggest plan with deterministic fallback`

---

### Task 5: Chores, submissions, approve/reject + redo nudge

**Files:**
- Create: `chore_service.dart`, kid `today_screen.dart`, `mark_done_screen.dart`, parent `approvals_screen.dart`
- Test: approve writes ledger via `splitCredit`; reject sets nudge and Today shows item

**Interfaces:**
- Produces: `submitChore(...)`, `approveSubmission(id)` (transactional ledger writes), `rejectSubmission(id, nudge)`

- [ ] **Step 1:** Failing tests for approve overshoot and reject→Today.

- [ ] **Step 2:** Implement submission flow. If `requires_photo` and no photo → block submit.

- [ ] **Step 3:** Parent Approval inbox: Approve / Reject+nudge.

- [ ] **Step 4:** Commit `feat: chore submit approve reject with ledger`

---

### Task 6: Photo assist + Storage + Goal Album

**Files:**
- Create: `photo-assist` edge function, album screens/services, image upload to `family_id/...` path
- Test: album delete removes row; non-visual chore cannot be created with `requires_photo: true` in AI accept validation (server or client assert)

**Interfaces:**
- Produces: `photoAssist(choreTitle, imageBytes) → {suggest: approve|reject, reason}`; parent final; `addToAlbum`, `deleteAlbumItem`

- [ ] **Step 1:** Upload on mark-done when required; call photo-assist; show suggestion on approval card.

- [ ] **Step 2:** Goal Album: list, add from approved submission, delete.

- [ ] **Step 3:** Privacy copy in album screen: demo/test data only.

- [ ] **Step 4:** Commit `feat: photo assist storage and goal album`

---

### Task 7: Parent home + weeks-to-goal card + polish copy

**Files:**
- Create/modify: parent `home_screen.dart`, goal detail weeks card, honesty banners

**Interfaces:**
- Produces: Home lists kids/goals/pending count; goal detail shows `weeks remaining`, suggested weekly top-up from last accepted `ai_plans`, progress from ledger sums (cap 100%)

- [ ] **Step 1:** Implement weeks-to-goal = max(1, ceil((target - goalBank) / weeklyTopup)) when topup > 0.

- [ ] **Step 2:** Banners: ledger not real money; photos demo-only.

- [ ] **Step 3:** Commit `feat: parent home and plan cards`

---

### Task 8: Demo seed walkthrough + README recording script

**Files:**
- Modify: `README.md`, create `docs/demo-video-script.md`

**Interfaces:**
- Produces: 1–3 min shot list matching Basics requirements

- [ ] **Step 1:** Script beats: role switch → New Goal → Suggest plan (show why) → Accept → Kid Today → mark done with photo → Parent approve → progress + overflow if cued → Album add/delete.

- [ ] **Step 2:** Manual dry-run on iOS simulator; fix blockers.

- [ ] **Step 3:** Commit `docs: demo video script`

---

### Task 9: Devpost project draft (no Final Submit)

**Files:**
- Devpost project for Build With AI: Basics; optional `docs/devpost-draft.md`

**Interfaces:**
- Produces: draft with repo URL, description, Built With; video URL when recorded

- [ ] **Step 1:** Create Devpost draft from README + design one-liner + what-you-learned stub.

- [ ] **Step 2:** Do **not** Final Submit without Anoop.

- [ ] **Step 3:** Note on deadline board: Build With AI → Do My Chore draft.

---

## Done when

- [ ] `scope.md` / `prd.md` / `spec.md` present
- [ ] Flutter demo loop filmable with role switch
- [ ] RLS on; ledger overshoot correct; reject redo works
- [ ] AI plan + photo assist have fallbacks
- [ ] Album deletable; privacy + money honesty in UI
- [ ] Devpost draft ready; Final Submit waits for Anoop

## Out of this plan

Mac Hermes hands-on App Store; real vision accuracy tuning; multi-family SaaS; Care Ladder work; portfolio positioning vs Shelter Needs.
