# Devpost draft: PayPal AI Hackathon (Goal Wallet)

Draft only. Do not Final Submit.

This is the Goal Wallet draft. `docs/devpost-draft.md` is the separate Build With AI: Basics draft. Leave that file as it is.

Hackathon: [PayPal AI Hackathon](https://paypalaihackathon.devpost.com/). Repo: https://github.com/pamu512/do-my-chore (`feat/goal-wallet`). Judge steps: `docs/paypal-goal-wallet-sandbox-runbook.md`.

## Project title

Do My Chore

## Tagline

Chore money that stays locked on the goal — even when a week gets skipped

## What it does

A parent is saving the real cost of a goal the kid is earning, such as the seeded Disneyland trip. Each week the parent can capture that week's amount into a PayPal sandbox business account. That captured balance is the pot.

The loop a judge can follow:

1. The kid earns the goal through weighted chores and sees percents only. On the kid screen, money in the pot is the funding ratio rendered as a percent plus the word "funded", and the line "Saved toward the goal". Dollars stay on the parent screen.
2. The parent creates a sandbox order for one funding week (`paypal-order`), approves it as the sandbox personal account, and captures it (`paypal-capture`). Capture is what lands in the business account. The edge stores the capture and one parent save.
3. If that week is skipped or declined, the week adds $0. PayPal is not called. The kid's funded percent stays where it was, and the goal date stays put. The weeks still left before that date are rewritten so they add up to what is still unpaid. The last week holds the leftover cents.
4. If the parent takes money out before the goal date, the app appends a row to `paypal_withdrawals` through `wallet-withdraw`. The kid's funded percent drops with the amount taken out. The remaining weeks are rewritten to the new unpaid amount. The captured PayPal rows stay as they were. The take-out does not call PayPal.

Skip, decline, and take-out math is deterministic. Suggest plan can still draft the original chore weights. It does not move the pot.

## How we built it

Postgres holds `goal_wallets`, `funding_milestones`, `paypal_transfers`, and `paypal_withdrawals`, with parent-only row level security on the funding tables. Kids do not get those tables. They call `goal_funding_percent`, which is captured minus withdrawn, divided by the goal amount, and never below zero.

Deno edges: `paypal-order`, `paypal-capture`, `funding-decline`, `wallet-withdraw`. Orders v2 uses intent `CAPTURE` against `https://api-m.sandbox.paypal.com`. Any other PayPal host is refused before a request.

The parent screen lists the weeks, sends a skip to `funding-decline`, and sends a take-out to `wallet-withdraw`. Create and capture stay on the two PayPal edges. The runbook has the curl steps, the env shape with empty values, and the Deno commands.

## Challenges

A skipped week had to leave the kid's funded percent alone, and a take-out had to lower it, using the same captured-minus-withdrawn rule. The unpaid remainder is split across Mondays left through the goal date, with the cent remainder on the last Monday. If the goal date is still ahead and no Monday remains, that remainder is one payment on the goal date.

A take-out could not be a negative `paypal_transfers` row. That table requires `amount >= 0`, a milestone, and a status of `created`, `captured`, `declined`, or `skipped`. Take-outs are their own append-only table. An amount above the captured balance minus earlier take-outs returns 409 and writes nothing.

## Accomplishments

- Sandbox Orders v2 create, buyer approval, and capture into the business account, with order id and capture id stored on `paypal_transfers`.
- Skip and decline record $0, leave the funded percent unchanged, and resplit the weeks still proposed.
- Mid-goal take-out is a parent ledger row. Captured transfers stay unchanged. The funded percent drops.
- The Orders client refuses a live PayPal host.
- Fixtures for the schedule and the wallet HTTP handlers cover the resplit and the over-withdraw rejection.

Evidence for the live sandbox capture and the withdraw ledger is local only, under `~/.config/ax/inbox`. It is not in this repo. Paths are in the runbook. Captioned app screenshots for this draft are local too, in `~/Documents/GitHub/dmc-demo/goal-wallet-gallery/` (11 PNGs with one-line captions), also not committed here.

## What we learned

Parents can trust the pot when a skipped week and a take-out follow one rule: only captured money counts, and the schedule after that is arithmetic. Labeling the take-out as a ledger, and the capture as sandbox, is what makes the demo judgeable.

## What's next

Final Submit waits until Anoop asks. Live charges, Holds, Payouts, refunds, and auto-pay stay out.

## Built with

flutter, dart, supabase (postgres, rls, edge-functions), deno, paypal orders v2 (sandbox)

## Honesty checklist

- [ ] Sandbox business account is the pot. No live charge in the copy.
- [ ] No Holds, Payouts, refunds, or auto-pay.
- [ ] Mid-goal take-out is described as a ledger row. No PayPal withdraw call.
- [ ] Kid screenshots show a funded percent, not dollars.
- [ ] No COPPA or kids-privacy compliance claim.
- [ ] `docs/devpost-draft.md` still describes Build With AI: Basics.
- [ ] Final Submit not pressed.

## Try it

Follow `docs/paypal-goal-wallet-sandbox-runbook.md` on `feat/goal-wallet`: one sandbox capture, one skip, one ledger take-out, then the Deno fixtures. Credentials stay outside the repo.
