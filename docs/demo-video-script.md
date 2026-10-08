# Do My Chore: Demo Video Script (1 to 3 min)

Target: [Build With AI: Basics](https://learn-ai-basics.devpost.com/) submission video.
Record on the iOS simulator, one take per beat, parent-led. All shots use the
seeded demo family (`parent@demo` / `kid@demo`) against local Supabase.

Model (rev 3): the kid earns 100% of the goal through weighted chores; the
parent plans the real cost and settles money offline. Kid screens show
percent only. No pocket, no chore dollars anywhere in the demo.

## Pre-flight (before recording)

- [ ] `supabase db reset` - fresh seed (Disneyland family trip $3500, 14 weeks,
      chores bed 40 / dishes 30 / laundry 20 / itinerary 10, accepted plan $250/wk)
- [ ] App running: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- [ ] Simulator: iPhone 17 Pro (or Air), 100% scale, clean home screen
- [ ] Optional: set an OPENAI_API_KEY as a function secret for the LLM path -
      but the demo is fully repeatable **without any key** (deterministic fallback)

## Beats (about 15-20s each)

| # | Shot | Action | Narration cue |
|---|------|--------|---------------|
| 1 | Parent Home (planner) | Disneyland card: Trip $3500, "Save $250/week for 14 weeks", saved-so-far bar, "Kid chore progress 0% (weights 100%)" | "Priya plans the real cost of the trip; the app keeps her honest about saving." |
| 2 | New Goal | Mode switch Family trip / Kid item, cost, date, "Allow makeup chores" off by default, Suggest plan: weekly save + weighted chores + why | "The AI drafts the save cadence and a habit plan whose weights add up to 100 percent." |
| 3 | Accept | Tap **Accept plan** | "She can edit anything before accepting." |
| 4 | **Role switch** | Tap **Kid** in the app bar - instant, no login | "One tap to Arjun's view. Percent only. No dollars on any kid screen." |
| 5 | Kid Today → Mark done | Open "Make your bed", see "each check-in adds +0.4%", take photo, submit | "Daily habits are worth big weight, paid out one small slice per check-in." |
| 6 | Parent approvals | Inbox shows "+0.4% · photo attached", approve | "Approving moves the kid bar a fraction of the weight. The parent never hands over cash in-app." |
| 7 | Progress | Kid bar ticks up; parent card shows saved-so-far after "I saved this week" | "Two parallel accountabilities: the kid keeps habits, the parent keeps the promise." |
| 8 | Makeup (optional beat) | Flip allow_makeup on the goal, parent sees the behind-pace card, adds a one-time makeup chore, kid completes it | "If he falls behind, she can add a catch-up chore. Her call, never automatic." |
| 9 | Goal Album | From the parent home, open the album, add a photo from an approval, delete one | "Approved photos become a memory album - and everything is deletable." |
| 10 | Close on banners | Show the honesty banner + README on screen | "A habit tracker for the kid, a financial planner for the parent. Built with Flutter, Supabase, and AI that knows parents make the final call." |

## Shot hygiene

- 1080p, simulator recording or QuickTime device-window capture
- Keep every beat under 20s; total 2:00-2:30
- No real names, no real photos - demo/test data only
- Say "suggest", never "verifies" - the parent always decides
- No dollar figures may appear on a kid screen during the video
