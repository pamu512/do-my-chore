# Do My Chore: Shared library habits across goals

**Date:** 2026-09-29 HKT  
**Status:** Locked for implement (Anoop locked this date)  
**Sits on:** rev-3 money model + V3 encouragement  
**Base:** current `main`. Do **not** touch `feat/nebius-token-factory` / Nebius PR #3.

## 1. Problem

A family can have two or more **active** goals at once (Ice cream at 100% once, Disneyland at 5% daily). The same real habit, make the bed, is suggested independently on each goal. Kid Today then lists the habit twice. Two photos, two Send to parent, two approvals. The kid did one thing.

## 2. Locked product rules

1. Age-based **chore library** entries have **stable catalog IDs**. AI Suggest plan MUST pick from that library. The same habit always uses the same id (`make-your-bed` is `make-your-bed` on every goal, every age band that includes it).
2. When two or more **active** goals for the family include the same `library_chore_id`, Kid Today shows **one** row. One check-in, one photo, one Send to parent.
3. On approve (and reject / send-back), apply to **all** active chore rows that share that library id. Each goal keeps its own `weight_pct` and cadence math. Ice cream 100% once vs Disneyland 5% daily is intentional.
4. **Custom** chores (parent-entered, no library id: makeup, later free-text) are **goal-private**: never merge, never appear on other goals’ Today as shared.
5. **No fuzzy title matching.** Sharing is library-id only. Two custom chores titled "Make your bed" stay two rows.
6. Kid UI remains **% only**. No dollars on kid screens.

## 3. Schema (small POC)

No `habit_checkins` table. Reuse `chores` + `chore_submissions`.

### `chore_library`

Catalog, not family data. Stable **text** slugs (not random UUIDs) so the same habit is the same id forever.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | text PK | slug, e.g. `make-your-bed` |
| `title` | text | display title |
| `cadence` | once \| daily \| weekly | library default |
| `requires_photo` | bool | visually verifiable only |
| `min_age` | int | inclusive |
| `max_age` | int | inclusive |

Seed extends the catalogs already used by `buildDeterministicPlan` / `suggest-plan` (kid 8+ vs little ≤7) plus the extra visually-verifiable titles already listed in `kVisuallyVerifiable`. `fold-the-laundry` is one id in both age bands.

RLS: authenticated read. Writes stay with migrations / service role.

### `chores.library_chore_id`

Nullable `text` FK → `chore_library(id)`.

- Plan-accepted rows: always set.
- Makeup / parent-typed rows: **null** (custom, goal-private).
- Backfill: exact title match to `chore_library.title` only. That is a one-time import, not runtime sharing.

## 4. Suggest plan

Deterministic builder and LLM path both emit `library_chore_id` on every chore.

- Age filter: `min_age <= kidAge <= max_age`.
- Deterministic plans keep the existing four-habit worked examples, now stamped with catalog ids.
- LLM prompt lists the age-filtered library **with ids**. Response must include `library_chore_id`. Unknown id → exact title match to library → else deterministic fallback. Never invent an id. Never fuzzy-match.

`validatePlan` / `acceptPlan` write `library_chore_id` onto `chores`. Initial plans without a catalog id are rejected.

## 5. Kid Today

`todayForKid` still returns one card per chore row. A pure helper `collapseTodayByLibraryId` then groups:

- `library_chore_id` present: one visible row per id.
- `library_chore_id` null: never grouped, even if titles match.

Collapsed row:

- Title from the library / first member.
- `requires_photo` if **any** member needs a photo.
- Row kind (open / next try / sent) is the most actionable member: open > next try > sent.
- Meta: cadence + “counts for N goals” when N > 1. Still % only, do not invent a single combined weight.
- `sharedChoreIds` lists every active matching chore id.

Day-done / pace math expands the cluster so each goal’s `weight_pct` and cadence still count.

## 6. Submit once

Mark Done / `submitChore` inserts one `chore_submissions` row **per** id in `sharedChoreIds` (the matched **active** chores). One photo upload; same `photo_url` on every row.

Custom (single id): unchanged.

## 7. Parent approve / send-back

Prefer **one parent action for the cluster**.

- Inbox may collapse pending rows that share a `library_chore_id` (shared photo) into one card.
- `approve_chore_submission` fans out: after flipping the chosen pending row, also approve other **pending** submissions for active, non-archived chores in the same family with the same non-null `library_chore_id`.
- Send-back / reject updates every pending submission in that cluster (same nudge).

Custom chores (null library id) never fan out.

Each goal’s progress is still `instance_credit_pct = weight_pct / expected_instances` on **that** chore’s approvals. A 100% once Ice cream chore and a 5% daily Disneyland chore both move when the cluster is approved; the percents stay different.

## 8. Non-goals

- No title/fuzzy merge. No merge of archived or non-active goals.
- No Nebius / token-factory edits.
- No kid-visible dollars.
- No new habit_checkins table in this POC.
- Do not merge until Anoop greenlights.

## 9. Tests

- Collapse: same library id → one row; null ids with identical titles stay two rows; different ids stay two rows.
- Multi-goal credit: one cluster approval credits each member with its own weight / cadence math.
- Submit helper: one action targets every shared chore id.
- `flutter test` green.
