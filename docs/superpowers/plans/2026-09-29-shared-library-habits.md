# Shared Library Habits Implementation Plan

> **For agentic workers:** Implement in this session. TDD: failing tests first.

**Goal:** One library habit is one Kid Today row across active goals; one submit / one parent decision; each goal keeps its own weight and cadence math.

**Architecture:** Extend the existing in-memory age catalogs into a `chore_library` table with stable text slugs. Stamp `chores.library_chore_id`. Collapse and fan-out in Dart (+ approve RPC). No `habit_checkins` table.

**Tech Stack:** Flutter `app/`, existing Supabase chores/submissions, `suggest-plan` edge function.

## Global Constraints

- Base = current `main`. Nebius branch untouched.
- Kid UI % only.
- Share by `library_chore_id` only. Custom (null) never merges.
- AI Suggest must emit catalog ids; same habit → same id.
- Approve/reject applies to every active chore row with that id.
- POC stays small: no new check-in table.

---

### Task 1: Spec + catalog ids in the existing plan builder

**Files:** spec (done), `app/lib/services/chore_library.dart`, `app/lib/services/ai_service.dart`, `supabase/functions/suggest-plan/index.ts`, `app/test/goal_service_test.dart`, `app/test/plan_validation_test.dart`

- [ ] Failing tests: deterministic plans stamp stable ids; same habit same id at age 9 and again at age 9; little-kid bed is `tidy-your-room` not `make-your-bed`; `validatePlan` rejects a plan chore with no library id.
- [ ] Implement `kChoreLibrary` + `libraryForAge`; `ChoreSpec.libraryChoreId`; deterministic catalogs use those ids; LLM prompt lists ids and remaps/falls back.
- [ ] `acceptPlan` writes `library_chore_id`. Makeup stays null.

### Task 2: Schema + seed backfill

**Files:** `supabase/migrations/20260929120000_shared_library_habits.sql`, `supabase/seed.sql`

- [ ] `chore_library` + `chores.library_chore_id` nullable FK.
- [ ] Seed the catalogs already in suggest-plan (plus extra visual titles).
- [ ] Exact-title backfill. Demo seed chores get the matching slugs.
- [ ] `approve_chore_submission` fans out to sibling pending rows with the same non-null library id on active chores.

### Task 3: Collapse + multi-goal credit (pure)

**Files:** `app/lib/services/chore_library.dart`, `app/lib/services/queries.dart`, `app/test/shared_library_habits_test.dart`

- [ ] Failing tests for collapse and cluster credit (Ice cream 100% once vs Disneyland 40% daily).
- [ ] `collapseTodayByLibraryId`, `collapsePendingByLibraryId`, `clusterRowKind`, `submissionChoreIds`, `clusterCreditPreviews`.

### Task 4: Flutter Today / Mark Done / Approvals

**Files:** `queries.dart`, `chore_service.dart`, `today_screen.dart`, `mark_done_screen.dart`, `approvals_screen.dart`, `app/test/kid_today_shared_habits_test.dart`

- [ ] Failing widget test: two bed cards with the same library id → one Today row; two custom "Make your bed" → two rows.
- [ ] `todayForKid` selects `library_chore_id` and collapses.
- [ ] Submit inserts one row per shared chore id (same photo).
- [ ] Approvals collapse; approve RPC fans out; reject updates the cluster.

### Task 5: `flutter test` green + draft PR
