# Do My Chore — Demo Video Script (1–3 min)

Target: [Build With AI: Basics](https://learn-ai-basics.devpost.com/) submission video.
Record on the iOS simulator, one take per beat, parent-led. All shots use the
seeded demo family (`parent@demo` / `kid@demo`) against local Supabase.

## Pre-flight (before recording)

- [ ] `supabase db reset` — fresh seed (Disneyland goal, 6 chores, accepted plan)
- [ ] App running: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- [ ] Simulator: iPhone 17 Pro (or Air), 100% scale, clean home screen
- [ ] Optional: set an OPENAI_API_KEY as a function secret for the LLM path —
      but the demo is fully repeatable **without any key** (deterministic fallback)

## Beats (≈15–20s each)

| # | Shot | Action | Narration cue |
|---|------|--------|---------------|
| 1 | Parent Home | Show goal card: progress bar, $/$500, pending-approvals count | "Priya wants her son Arjun to save $500 for Disneyland." |
| 2 | New Goal → Suggest plan | Tap New Goal, type "Camping trip, $300", tap **Suggest plan** — show the **why** card and the chore list | "The AI drafts a save plan — weekly top-up, chores, and a plain-English why." |
| 3 | Accept | Tap **Accept plan** | "She edits anything she disagrees with, then accepts." |
| 4 | **Role switch** | Tap **Kid** in the app bar — instant, no login | "One tap switches to Arjun's view — same family, real permissions." |
| 5 | Kid Today → Mark done | Open a photo chore, **Take a photo**, submit | "Chores that need proof ask for a photo — reading time doesn't." |
| 6 | Back to Parent → Approvals | Open the approval inbox, approve | "The parent approves — $4 lands in the goal, $1 in pocket." |
| 7 | Progress + overshoot | Show the Kid bar move; if cued: approve one more chore after a big top-up to show goal capping at $500 with the remainder flowing to pocket | "The goal never overshoots — extra earnings spill into pocket money." |
| 8 | Reject → redo nudge | Reject a submission with a nudge; switch to Kid, show the retry card on Today | "Rejected? The chore comes back with a kind nudge, not a punishment." |
| 9 | Goal Album | From the parent home, open the album, add a photo from an approval, delete one | "Approved photos become a memory album — and everything is deletable." |
| 10 | Close on banners | Show the honesty banner + README on screen | "In-app money only, parents settle offline, test photos only. Built with Flutter, Supabase, and AI that knows when parents make the final call." |

## Shot hygiene

- 1080p, simulator ⌘+R recording or QuickTime device-window capture
- Keep every beat under 20s; total 2:00–2:30
- No real names, no real photos — demo/test data only
- Say "suggest", never "verifies" — the parent always decides
