# Do My Chore

**Parent sets the goal, AI plans the save, kids earn it.** A Flutter + Supabase POC built for [Build With AI: Basics](https://learn-ai-basics.devpost.com/).

A parent creates a goal (e.g. *Disneyland, $500, by December*), gets an AI-suggested save plan — weekly top-up plus chores, with a plain-language "why" — and kids complete chores (photo proof where it makes sense). Approvals credit a **goal bank** with overflow landing in the kid's **pocket**, and chore photos collect into a deletable **Goal Album**.

## The demo loop

1. Parent creates goal → **AI Suggest plan** (weekly top-up + 4–8 chores + why) → edit → accept
2. In-app **role switch** to Kid → Today list → mark done (camera when the chore needs visual proof)
3. Role switch back → **approve** (AI photo assist suggests, parent decides) or **reject with a nudge** → rejected chores return to Kid Today
4. Ledger credits **goal bank vs pocket** (overshoot fills the goal, remainder goes to pocket) → progress bar fills
5. Approved photos can be added to the **Goal Album** — and any album item can be deleted

## Architecture

- **Flutter** (iOS simulator primary) — Parent ↔ Kid role switch on one seeded demo family
- **Supabase** — Auth, Postgres with **RLS on every family-scoped table**, Storage for photos, Edge Functions for AI
- **`ledger_entries` is the money source of truth** — balances are summed on read; there is no cached balance column
- Both AI moments (**Suggest plan**, **Photo assist**) run deterministically with **zero API keys**; set `OPENAI_API_KEY` to upgrade them

## Run it

### 1. Supabase (local via Docker)

```bash
brew install supabase/tap/supabase   # once
supabase start                       # from repo root; starts Postgres/Auth/Storage/Functions
supabase db reset                    # applies migrations + demo seed
supabase status                      # note the API URL and anon key
```

### 2. Flutter app

```bash
cd app
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key from supabase status>
```

### 3. Demo accounts

| Account | Password |
|---|---|
| `parent@demo` | `demo1234` |
| `kid@demo` | `demo1234` |

These are **demo-only credentials for a local instance** — never reuse them anywhere real. The seeded family has one goal ("Disneyland") and a mix of chores with and without photo requirements.

## Honesty notices

- **Money:** the ledger is in-app only. Nothing here is a bank, card, or payment rail; parents settle real money **offline**. Pocket cash-out is a family conversation, not a feature.
- **Photos & kids:** all photos and kid accounts in this demo are **test data only**. This POC does not implement COPPA-style verifiable parental consent — that is a hard requirement before any real family uses something like this.
- **AI:** photo assist only *suggests*; **the parent is always final**. No claim of perfect verification is made anywhere.

## Repository docs

- [`scope.md`](scope.md) · [`prd.md`](prd.md) · [`spec.md`](spec.md) — planning docs (Devpost Learn skill-pack substance)
- [`docs/superpowers/specs/2026-09-27-do-my-chore-design.md`](docs/superpowers/specs/2026-09-27-do-my-chore-design.md) — authoritative design (rev 2)
- [`docs/superpowers/plans/2026-09-27-do-my-chore.md`](docs/superpowers/plans/2026-09-27-do-my-chore.md) — task-by-task implementation plan
- [`docs/superpowers/specs/2026-09-29-encouragement-layer-v3.md`](docs/superpowers/specs/2026-09-29-encouragement-layer-v3.md) — V3 encouragement layer (locked)
- [`docs/superpowers/plans/2026-09-29-encouragement-layer-v3.md`](docs/superpowers/plans/2026-09-29-encouragement-layer-v3.md) — V3 implementation plan
- [`docs/demo-video-script.md`](docs/demo-video-script.md) — 1–3 min demo shot list

## Layout

```
app/          Flutter app (lib/features/{parent,kid,shell}, services, models)
supabase/     config.toml, migrations/, seed.sql, functions/{suggest-plan,photo-assist}
docs/         design spec, implementation plan, demo script
```

## License

MIT — see [LICENSE](LICENSE).
