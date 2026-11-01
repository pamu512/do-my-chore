# Goal Wallet sandbox runbook

Judge path for the PayPal AI Hackathon build on `main` (default branch). Sandbox only. This file does not Final Submit.

The parent app records a skip and a mid-goal take-out. Create and capture run on the `paypal-order` and `paypal-capture` edges. The app does not call those two functions.

Local demo login is `parent@demo` / `demo1234` (see the README). `kid@demo` is rejected with 403.

## 1. Orders v2: create, approve, capture into the business pot

Money moves only on capture. The client calls `https://api-m.sandbox.paypal.com` with intent `CAPTURE`. OAuth is `client_credentials` against `/v1/oauth2/token`. A live host is refused before any request.

The buyer is the sandbox personal account. The pot is the sandbox business account. Set `PAYPAL_BUSINESS_EMAIL` to that business address when you want it written as the order payee. With the email unset, the order has no payee override and the capture settles on the merchant that owns the client id.

### Prep

From the repo root:

```bash
supabase start
supabase db reset
supabase status
```

`db reset` loads the seeded Disneyland goal (`00000000-0000-0000-0000-0000000000b1`, family `00000000-0000-0000-0000-000000000001`) and does not insert a wallet. After reset, run this once against the DB URL from `supabase status`:

```sql
insert into public.goal_wallets (id, family_id, goal_id, goal_amount, goal_date)
select
  '00000000-0000-0000-0000-0000000000d1',
  g.family_id,
  g.id,
  g.target_amount,
  g.target_date
from public.goals g
where g.id = '00000000-0000-0000-0000-0000000000b1';

insert into public.funding_milestones
  (id, wallet_id, family_id, due_date, proposed_amount, status)
select
  '00000000-0000-0000-0000-0000000000e1',
  '00000000-0000-0000-0000-0000000000d1',
  g.family_id,
  current_date,
  4.00,
  'proposed'
from public.goals g
where g.id = '00000000-0000-0000-0000-0000000000b1';
```

`4.00` is the same amount as the completed sandbox capture in the G0 memo. It keeps a judge run small.

Put the PayPal keys in `supabase/functions/.env` (gitignored; see section 4) and restart local functions so the process reads them. `supabase start` injects `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

Sign in as the parent and keep `access_token`:

```bash
curl -sS -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"email":"parent@demo","password":"demo1234"}'
```

`$ANON` is the anon key from `supabase status`. Use the `access_token` from that response as the `Bearer` value (`$PARENT_JWT`) in the create, capture, decline, and withdraw calls. Do not commit either value.

### Create

```bash
curl -sS -X POST "http://127.0.0.1:54321/functions/v1/paypal-order" \
  -H "Authorization: Bearer $PARENT_JWT" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"milestone_id":"00000000-0000-0000-0000-0000000000e1"}'
```

Expect `200` and `{ "order_id", "approve_url" }`. The edge inserts `paypal_transfers` with `status = created`, `amount = 0.00`, `order_id` set, `capture_id` null. The milestone stays `proposed` until capture.

Calling create again while that order is still uncaptured returns `{ "order_id", "reused": true }` and does not include `approve_url`. Keep the first approval link. After a successful capture the milestone is settled, and create returns `409` `milestone already settled`.

The milestone must be `proposed` or `approved`, currency `USD`, and `proposed_amount` greater than 0. Anything else is `409`.

### Approve

Open `approve_url` and approve as the sandbox personal (buyer) account. The edge does not approve the order.

### Capture

```bash
curl -sS -X POST "http://127.0.0.1:54321/functions/v1/paypal-capture" \
  -H "Authorization: Bearer $PARENT_JWT" \
  -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d '{"order_id":"ORDER_ID_FROM_CREATE"}'
```

Expect `200` and `{ "order_id", "capture_id", "amount", "wallet_status" }`. PayPal must return a `COMPLETED` capture in USD with a positive amount. The edge then:

- updates that transfer to `status = captured` with the capture id and amount
- marks the milestone `captured`
- inserts one `parent_save_entries` row whose note is `paypal capture <capture_id>`
- rewrites future `proposed` milestones so they sum to the shortfall

A second capture of the same order returns `200` with the same capture id and does not create a second transfer.

Check the ledger (superuser SQL; `goal_funding_percent` itself requires a family JWT and raises `family members only` otherwise):

```sql
select status, amount, order_id, capture_id
from public.paypal_transfers
where milestone_id = '00000000-0000-0000-0000-0000000000e1';
```

Expect one `captured` row for `4.00`.

## 2. Skip or decline

`POST /functions/v1/funding-decline` with a parent JWT:

```json
{ "milestone_id": "<uuid>", "decision": "skipped" }
```

`decision` may be `skipped` or `declined`. The parent screen sends `skipped`. Both record `$0` and do not call PayPal.

Pick a `milestone_id` that is still `proposed`; after the capture those rows are the regenerated tail:

```sql
select id, due_date, proposed_amount
from public.funding_milestones
where wallet_id = '00000000-0000-0000-0000-0000000000d1'
  and status = 'proposed'
order by due_date;
```

Expect `200` and `{ "milestone_id", "decision", "wallet_status", "funding_percent" }`.

What changes:

- The milestone status becomes `skipped` or `declined`.
- A `paypal_transfers` row is inserted with `amount = 0.00`, `order_id` null, `capture_id` null, and that same status.
- Captured cents do not change, so the kid percent does not change. Kid percent is `goal_funding_percent`: `greatest(0, sum(captured) - sum(withdrawn)) / goal_amount`. The kid screen shows that ratio as a percent and the line "Saved toward the goal". It does not show dollars.
- Future rows still in `proposed` are deleted and rewritten. `shortfall = max(0, goal_amount - effective_captured)` where `effective_captured = max(0, captured - withdrawn)`. `periods_left` is each Monday UTC from the next Monday on or after today through `goal_date`. If that list is empty and the goal date is still today or later, one period falls on the goal date. Amounts are `shortfall / periods_left` in cents, and the last period keeps the remainder.
- An open `created` order is pinned: that milestone stays, and its `proposed_amount` is reserved out of the shortfall before the split.
- Skipped and declined rows stay on their due date. Sum only rows still `proposed` when you check the tail. The old `proposed_amount` on a skipped row is not collected.
- If no period remains and open orders do not cover the shortfall, wallet status is `short`. Dates past `goal_date` are not added.

A milestone with a `created` or `captured` transfer cannot be skipped (`409`, `milestone has an open paypal order` or `milestone already settled`). Skip a later `proposed` row that has no transfer. After the `$4.00` capture, those rows are the regenerated tail. `funding_percent` in the response stays at the post-capture ratio. The goal date on the wallet stays the seeded goal date.

## 3. Mid-goal take-out

`POST /functions/v1/wallet-withdraw` with a parent JWT. `amount` is a decimal string. A JSON number is `400`.

```json
{ "wallet_id": "00000000-0000-0000-0000-0000000000d1", "amount": "1.00", "note": "sandbox take-out" }
```

`note` is optional, stored as `""` when omitted, and rejected over 500 characters.

Expect `200` and `{ "wallet_id", "amount", "wallet_status", "funding_percent" }`.

This is a ledger row. The edge inserts `paypal_withdrawals` (`amount > 0`, parent insert and select only, no update or delete policy). It does not call PayPal. There is no withdraw, payout, or refund request. Captured `paypal_transfers` rows are not updated. The kid percent drops because withdrawn cents now count. Future `proposed` amounts are resplit to the new shortfall with the same Monday rule and the cent remainder on the last period.

After a `$4.00` capture, `"1.00"` leaves effective captured at `$3.00`. `"5.00"` is over the remaining balance and returns `409` `withdraw exceeds captured balance` with no new row.

The captured dollars stay in the sandbox business account. The ledger is the parent's record that some of that pot was taken out before the goal date.

## 4. Environment

Required shape. Leave the values blank in git. Do not paste client ids, secrets, access tokens, or account emails into this repo, a Devpost field, or a log.

```
PAYPAL_CLIENT_ID=
PAYPAL_CLIENT_SECRET=
PAYPAL_MODE=sandbox
PAYPAL_BUSINESS_EMAIL=
```

On a machine that already has the sandbox app, the untracked source file is `~/.config/ax/secrets/paypal-sandbox.env`. Copy the values into `supabase/functions/.env` (gitignored) or `supabase/.env` (also gitignored). Restart functions after a change.

What the edges actually read:

| Variable | Role |
|---|---|
| `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET` | Required. Missing either returns `500` `paypal is not configured`. |
| `PAYPAL_MODE` | File marker. The client does not read it. |
| `PAYPAL_API_BASE` or `PAYPAL_HOST` | Optional. Must be exactly `https://api-m.sandbox.paypal.com`. Anything else throws before a request and the caller gets `500` `paypal is not configured`. Unset uses that sandbox origin. |
| `PAYPAL_BUSINESS_EMAIL` | Optional payee on the order. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Required. Injected by `supabase start`. |

`PAYPAL_BUSINESS_ACCOUNT_ID` and `PAYPAL_PERSONAL_ACCOUNT_ID` may sit in the secrets file. The edges do not read them. The personal account is only the buyer who opens `approve_url`.

## 5. Deno fixtures

From the repo root. These tests do not call PayPal and do not read the secrets file.

```bash
deno test --allow-env --allow-read \
  supabase/functions/_shared/funding_schedule_test.ts \
  supabase/functions/_shared/wallet_http_test.ts
```

A good run ends `ok` and exit 0. They cover the skip resplit (captured cents unchanged, future proposed cents sum to the shortfall, remainder on the last period) and the withdraw ledger (percent drops, captured transfers stay byte-identical, an over-withdraw returns 409 with no writes).

The Orders client fixture is separate:

```bash
deno test --allow-env --allow-read \
  supabase/functions/_shared/paypal_orders_test.ts
```

## 6. Evidence memos (do not commit)

G0, one completed sandbox capture persisted on `paypal_transfers`:

- `~/.config/ax/inbox/paypal-goal-wallet-g0-capture-20261019.md`

That memo names the run logs `~/.config/ax/runs/g0-evidence-close-20261019.log` and `~/.config/ax/runs/g0-evidence-close-20261019-b.log`. Those re-gates did not create a second order and did not write tokens.

Withdraw ledger, no PayPal withdraw call:

- `~/.config/ax/inbox/paypal-goal-wallet-g1-withdraw-done-20261020.md`
- `~/.config/ax/inbox/paypal-goal-wallet-g1-withdraw.DONE-EVIDENCED`

## Out of scope

Live charges, Holds, Payouts, refunds, auto-pay, and Final Submit.
