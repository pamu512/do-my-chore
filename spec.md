# Do My Chore — Technical Spec

> Rev 3 money model is authoritative: [`docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md`](docs/superpowers/specs/2026-09-27-do-my-chore-money-model-rev3.md) · Plan: [`docs/superpowers/plans/2026-09-27-do-my-chore-money-model-rev3.md`](docs/superpowers/plans/2026-09-27-do-my-chore-money-model-rev3.md)

## Stack

- **Flutter 3.22+ (Dart 3)** - `supabase_flutter`, `flutter_riverpod`, `go_router`, `image_picker`, `cached_network_image`; iOS simulator is the demo target
- **Supabase** - Auth, Postgres with RLS, Storage (photos), Edge Functions (Deno) for AI
- **Tests** - `dart_test` / `flutter_test`; TDD per task (failing test -> implement -> pass -> commit)

## Data model

| Table | Key columns | Notes |
|---|---|---|
| `families` | id | one seeded demo family |
| `profiles` | id (auth uid), family_id, role `parent`\|`kid`, display_name | RLS: caller's family |
| `goals` | family_id, kid_id, title, `goal_mode` family_trip\|kid_item, target_amount (cost), target_date, `allow_makeup`, status | cost is the parent's number |
| `chore_library` | id (stable text slug), title, cadence, requires_photo, min_age, max_age | age-keyed catalog |
| `chores` | goal_id, kid_id, title, `cadence` once\|daily\|weekly, `weight_pct` > 0, `requires_photo`, `is_makeup`, `is_bonus`, `library_chore_id` nullable | weights may sum over 100; share by library id only |
| `chore_submissions` | chore_id, family_id, kid_id, status pending\|approved\|rejected, photo_url, reject_nudge | retry = new row |
| `parent_save_entries` | family_id, goal_id, amount > 0, note, created_by | parent's offline money log |
| `ai_plans` | goal_id, suggestion jsonb (`weekly_parent_save`, weights), accepted | last accepted feeds the home card |
| `album_items` | goal_id, photo_url, chore_submission_id?, caption?, added_by | deletable by parent |

## Progress rules (rev 3, locked)

1. The kid earns **100%** of the goal through chore progress; the parent funds the real cost separately.
2. Expected instances until `target_date`: once = 1, weekly = N, daily = 7*N (N = ceil days/7, min 1).
3. `instance_credit_pct = weight_pct / expected_instances`; one approval adds one credit.
4. Kid bar = min(100, sum of approved credits). A chore never contributes more than its full weight.
5. Weights may sum **over 100%** (oversubscribe = deliberate slack).
6. `is_behind_pace`: linear projection of current % to the target date falls short of 100 (equivalently `progress < 100 * weeks_elapsed / weeks_n`).
7. Approve RPC flips submission status only; **no ledger writes from chore rewards** (rev 2 overshoot-to-pocket is retired from the progress spine).
8. Makeup chores: `allow_makeup` default false; when on, the parent may add one-time `is_makeup` chores; never automatic.
9. Kid UI renders percent only. Dollars exist only on parent screens (cost, save cadence, saved-so-far).

Dart implementation:

```dart
// chore_progress_math.dart (pure)
int weeksRemaining({required DateTime today, required DateTime targetDate});
int expectedInstances({required String cadence, required int weeksN});
double instanceCreditPct({required double weightPct, required int expectedInstances});
double kidProgressPct({required chores, required int weeksN});   // caps at 100
bool isBehindPace({required double progressPct, required int weeksN, required int weeksElapsed, required double planWeightSum});

// ledger_math.dart (parent planner)
double suggestedSavePerWeek({required double cost, required int weeksN});  // cost / weeks
double parentSaveProgress({required double saved, required double cost});  // caps at 1
```

## RLS & storage

- RLS on all family-scoped tables incl. `parent_save_entries` (family read, parent insert); policies match `auth.uid() -> profiles.family_id`; role checks where needed (approve, saves, album delete = parent).
- Storage bucket paths prefixed `family_id/...`; write from kid submit, read from family, delete by parent.
- Verified by `scripts/rls_probe.py`: a kid session cannot read another family's rows.

## AI surfaces

Shared helper: `supabase/functions/_shared/llm.ts`. Selection order is `NEBIUS_API_KEY` (Token Factory + Nemotron) → `OPENAI_API_KEY` (gpt-4o-mini) → deterministic / abstain. Nebius is never required.

### POST /functions/v1/suggest-plan

Input `{ title, targetAmount, targetDate, kidAge }` -> `{ weekly_parent_save, chores: [{library_chore_id, title, cadence, weight_pct, requires_photo, is_makeup}], why }`.
- Chores MUST come from `chore_library` (stable catalog ids). Same habit → same id. Unknown id falls back to exact title match, else deterministic.
- With a key (`NEBIUS_API_KEY` or `OPENAI_API_KEY`): LLM generates the plan from the age-filtered library; the response is validated (weights >= 100, else fallback to deterministic).
- Without a key: **deterministic builder** (worked-example weights summing to exactly 100, save = cost / weeks). Same JSON shape either way. Flutter still uses the local builder when the function is unreachable.

### POST /functions/v1/photo-assist

Input `{ choreTitle, image }` -> `{ suggest: approve|reject|abstain, reason }`.
- Vision prompt only for visually verifiable chores; abstains otherwise; **parent is always final**.

### POST /functions/v1/goal-cost-orchestrate

Input `{ title, targetAmount, targetDate, goalMode }` -> `{ estimate: {low, likely, high, rationale, provider}, weekly_save_suggestion, deals, deal_search }`.
- New function (do not overload suggest-plan). Parent-only, after Accept. Optional `TAVILY_API_KEY` for deals under the likely budget; without it, estimate still returns and `deal_search` is `skipped`.
- Without an LLM key: deterministic 80/100/125 bands around the parent's entered cost.

## Auth & demo UX

- Email/password auth; seeded `parent@demo` / `kid@demo` / `demo1234` (documented as demo-only).
- Demo role switch: two pre-authenticated clients, one toggle - no login waits in the video.

## Configuration

- App: `--dart-define=SUPABASE_URL=... SUPABASE_ANON_KEY=...` (and optional `DEMO_WALK=true` for the simulator walkthrough camera stub)
- Functions secrets (all optional): `NEBIUS_API_KEY`, `OPENAI_API_KEY`, `TAVILY_API_KEY`, plus optional `NEBIUS_BASE_URL` / `NEBIUS_VISION_BASE_URL` / `NEBIUS_TEXT_MODEL` / `NEBIUS_VISION_MODEL` overrides. Vision calls use `NEBIUS_VISION_BASE_URL` when set, else `NEBIUS_BASE_URL`. Absence degrades to fallbacks, never crashes. See [`docs/nebius-token-factory.md`](docs/nebius-token-factory.md).
- Local dev: Supabase CLI via Docker (`supabase start`); iOS simulator reaches `127.0.0.1`.

## Testing

- `chore_progress_math_test.dart` - instance credits, Disneyland 40/30/20/10 perfect streak = 100, oversubscribe cap, behind-pace
- `ledger_math_test.dart` - suggested saves (250/wk worked example), save progress cap
- `plan_validation_test.dart` - weights >= 100, cadence validity, no makeup in plans, photo rule
- `overshoot_test.dart` - approval credit previews + submission state machine
- `goal_service_test.dart` - deterministic fallback shape, weights sum, weekly save
- `cost_estimate_test.dart` - deterministic 80/100/125 bands, deal budget filter, orchestrate parse, lock payload
- `widget_role_switch_test.dart` / `widget_test.dart` - shell renders both roles
- RLS check - cross-family read denied for kid session
