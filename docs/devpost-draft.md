# Devpost Draft — Build With AI: Basics

> DRAFT ONLY. **Do not Final Submit without Anoop.** Deadline ~2026-10-27 05:00 HKT.

## Project title

Do My Chore

## One-liner (≤200 chars)

The kid earns the goal 100% through weighted habit chores; the parent funds the real cost with an AI-planned save schedule. Two accountabilities, one goal.

## Description

Families want kids to earn toward **real goals** - a family trip, a skateboard - not just receive a vague weekly allowance. Allowance apps either gamify chores with fake money or hand kids a debit card. Do My Chore splits the bargain honestly:

**The kid's path is habit.** Every chore has a cadence (once, daily, weekly) and a weight. "Make your bed" daily might be worth 40% of the goal, paid out one tiny slice per check-in. The kid's screen shows **only a percent bar** - no dollars, no coins, no store. Reach 100% and the goal is earned. Parents can deliberately oversubscribe (weights above 100%) so a few skipped days don't sink the plan.

**The parent's path is the promise.** The same app is a financial planner for the real cost: Disneyland is $3,500, 14 weeks out, so the parent saves about $250 a week. A manual "I saved this week" log keeps the promise visible. Money is settled offline - no bank, no card, no KYC.

**AI where it helps, fenced where it must be:**

1. **Suggest plan** - given the goal, cost, date, and kid's age, the AI proposes a weekly parent save and 4-8 weighted chores whose weights sum to at least 100%, with a "why" in plain parent language. With no API key, a deterministic builder produces the same shape - the demo never depends on a key.
2. **Photo assist** - for chores a parent can verify by looking, it *suggests* approve/reject. Trust-based chores (reading time) never ask for photos. The parent is always final.

**Makeup, not bailout:** if the goal allows it and the kid is behind pace, the parent can add one-time catch-up chores. Off by default, never automatic.

## What we learned building with AI

The hardest part was not generation, it was **fencing**: making the AI's plan land inside rules a family can trust (weights that sum to at least 100, photos only on visually verifiable chores, makeup never auto-added). The deterministic fallback forced the prompt to be honest - if the fallback can't cheat, the prompt can't either.

## Links

- Repo: https://github.com/pamu512/do-my-chore
- Video: TODO (record per `docs/demo-video-script.md`)

## Built with

flutter, dart, supabase (postgres, rls, storage, edge-functions), deno, openai (optional), python

## Honesty checklist (must survive review)

- [ ] No banking / card / KYC claims anywhere in copy or screenshots
- [ ] No COPPA or kids-privacy compliance claims; demo photos labeled test data
- [ ] AI described as assistive ("suggests"), parent always final
- [ ] Kid screens show percent only - no dollar figures in kid screenshots
- [ ] Demo video shows role switch, AI weight plan, parent save log, album delete

## Submission checklist

- [ ] Video recorded (2:00-2:30) and uploaded
- [ ] Repo public with README quickstart verified end-to-end
- [ ] scope.md / prd.md / spec.md present and matching rev 3
- [ ] Final Submit **with Anoop present**
