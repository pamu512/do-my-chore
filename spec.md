# Do My Chore — Technical Spec

> Design rev 2 authoritative: [`docs/superpowers/specs/2026-09-27-do-my-chore-design.md`](docs/superpowers/specs/2026-09-27-do-my-chore-design.md) · Implementation plan: [`docs/superpowers/plans/2026-09-27-do-my-chore.md`](docs/superpowers/plans/2026-09-27-do-my-chore.md)

## Stack

- **Flutter 3.22+ (Dart 3)** — `supabase_flutter`, `flutter_riverpod`, `go_router`, `image_picker`, `cached_network_image`; iOS simulator is the demo target
- **Supabase** — Auth, Postgres with RLS, Storage (photos), Edge Functions (Deno) for AI
- **Tests** — `dart_test` / `flutter_test`; TDD per task (failing test → implement → pass → commit)

## Data model

| Table | Key columns | Notes |
|---|---|---|
| `families` | id | one seeded demo family |
| `profiles` | id (auth uid), family_id, role `parent`\|`kid`, display_name | RLS: caller's family |
| `goals` | family_id, title, target_amount > 0, target_date, status | **no balance column** |
| `chores` | goal_id, title, reward_amount, default_split_goal_pct, requires_photo bool | photo only on visually verifiable chores |
| `chore_submissions` | chore_id, kid_id, status pending\|approved\|rejected, photo_url, ai_photo_result jsonb, reject_nudge | retry = new row |
| `ledger_entries` | family_id, kind `goal_credit`\|`pocket_credit`\|`parent_topup`, amount, goal_id?, submission_id?, created_at | **source of truth** |
| `ai_plans` | goal_id, suggestion jsonb, accepted bool | last accepted feeds weeks-to-goal |
| `album_items` | goal_id, photo_url, chore_submission_id?, caption?, added_by | deletable by parent |

## Money rules (locked)

1. Balances are **computed on read**: `goal_bank = Σ goal_credit + Σ parent_topup (per goal)`; `pocket = Σ pocket_credit` (per family). Demo scale — no caching.
2. **Overshoot:** a credit that would push goal-bank past `target_amount` credits only up to the target as `goal_credit`; the remainder is written as `pocket_credit` **in the same transaction**.
3. Progress bar = min(1, goal_bank / target_amount).
4. Weeks-to-goal card = `max(1, ceil((target − goal_bank) / weekly_topup))` when `weekly_topup > 0`; "top up now" otherwise.
5. UI copy: in-app ledger only; **parent settles real money offline**. No spend/withdraw product in the POC.

Dart implementation lives in `app/lib/services/ledger_math.dart`:

```dart
BalanceSummary sumLedger(List<LedgerEntry> entries);
({double goalCredit, double pocketCredit}) splitCredit({
  required double amount, required double goalBalance, required double targetAmount,
});
```

## RLS & storage

- RLS enabled on **all** family-scoped tables; policies match `auth.uid() → profiles.family_id`; role checks where needed (approve/album-delete = parent).
- Storage bucket paths prefixed `family_id/...`; write from kid submit, read from family, delete by parent.
- Verified in Task 1: a kid session cannot read another family's rows.

## AI surfaces

### POST /functions/v1/suggest-plan

Input `{ title, targetAmount, targetDate, kidAge }` → `{ weekly_topup, chores: [{title, reward, requires_photo, split_goal_pct}], why }`.
- With `OPENAI_API_KEY`: LLM generates the plan; prompt demands **plain parent-language "why"**, 4–8 chores, `requires_photo` only on visually verifiable ones.
- Without a key: **deterministic builder** from amount ÷ weeks (≥4 chores, sensible split percentages, template "why"). Same JSON shape either way; Dart mirror of the fallback is unit-tested.

### POST /functions/v1/photo-assist

Input `{ choreTitle, image }` → `{ suggest: approve|reject|abstain, reason }`.
- Vision prompt only for visually verifiable chores; abstains with a reason otherwise; **parent is always final** — suggestion renders on the approval card, never auto-applies.

## Auth & demo UX

- Email/password auth; seeded `parent@demo` / `kid@demo` (passwords documented in README as demo-only).
- Demo role switch: one session with `activeProfileId` toggle (Parent ↔ Kid) so the video has no login waits.

## Configuration

- App: `--dart-define=SUPABASE_URL=... SUPABASE_ANON_KEY=...`
- Functions secrets: `OPENAI_API_KEY` optional — absence must degrade to fallbacks, never crash.
- Local dev: Supabase CLI via Docker (`supabase start`); iOS simulator reaches `127.0.0.1`. Hosted deploy happens only for the demo video.

## Testing

- `ledger_math_test.dart` — splitCredit overshoot + under-target; sumLedger goal vs pocket; progress cap
- `overshoot_test.dart` — end-to-end approval writes both entries in one transaction
- `goal_service_test.dart` — deterministic fallback ≥4 chores, `why` non-empty
- `widget_role_switch_test.dart` — toggle renders Parent Home vs Kid Today
- RLS check — cross-family read denied for kid session
