# Devpost Draft — Build With AI: Basics

> DRAFT ONLY. **Do not Final Submit without Anoop.** Deadline ~2026-10-27 05:00 HKT.

## Project title

Do My Chore

## One-liner (≤200 chars)

Parent sets the goal, AI plans the save, kids earn it — chores with photo proof, a goal bank that never overshoots, and a deletable memory album.

## Description

Families want kids to earn toward **real goals** — Disneyland, camping, a game — not just receive a vague weekly allowance. Parents need a plan to save; kids need clear chores and visible progress.

**Do My Chore** is a Flutter + Supabase proof of concept for the full loop:

1. A parent creates a goal (e.g. *Disneyland, $500, by December*) and gets an **AI-suggested save plan**: a weekly parent top-up, 4–8 age-appropriate chores, and a "why this plan" written in plain parent language. The parent edits anything, then accepts.
2. Kids see **Today's chores**. Chores that a parent can verify by looking (cleaned the table) ask for a photo; trust-based ones (read 20 minutes) never do.
3. The parent **approves or rejects**. An AI photo assist *suggests* — the parent always decides. Rejected chores return to the kid with a kind nudge, not a punishment.
4. Approvals credit a **goal bank**; if an approval would push past the target, the goal fills exactly and the remainder flows into the kid's **pocket**. Both entries write in one atomic transaction — the ledger is the source of truth and balances are computed on read.
5. Approved photos collect into a **Goal Album** that the parent can delete from at any time.

**What we learned building with AI:** the highest-value AI moment isn't verification — it's *plaining*. The deterministic fallback (same JSON shape, no API key) forced the LLM prompt to be honest: photo-required only on visually verifiable chores, and a "why" a tired parent actually wants to read.

## Links

- Repo: https://github.com/pamu512/do-my-chore
- Video: TODO (record per `docs/demo-video-script.md`)

## Built with

flutter, dart, supabase (postgres, rls, storage, edge-functions), deno, openai (optional), python

## Prizes / tracks

Build With AI: Basics — general track only.

## Honesty checklist (must survive review)

- [ ] No banking / card / KYC claims anywhere in copy or screenshots
- [ ] No COPPA or kids-privacy compliance claims; demo photos labeled test data
- [ ] AI described as assistive ("suggests"), parent always final
- [ ] Demo video shows role switch, AI plan why, overshoot-to-pocket, album delete

## Submission checklist

- [ ] Video recorded (2:00–2:30) and uploaded
- [ ] Repo public with README quickstart verified end-to-end
- [ ] scope.md / prd.md / spec.md present (skill-pack artifacts)
- [ ] Final Submit **with Anoop present**
