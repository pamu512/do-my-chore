# Encouragement Layer V3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the V3 emotional feedback layer (next-try, day/goal celebration, soft pace) on top of the shipped rev-3 % / $ split without new schema.

**Architecture:** Pure helpers in `encouragement.dart` decide row kind, day-done, today's % chip, pace copy, and banned-word checks from data `todayForKid` already fetches (`status`, `reject_nudge`, `created_at`) plus existing `isBehindPace` / `instanceCreditPct`. Presentational widgets render Ledger chrome. Approvals **Send back** sheet writes the edited note through the existing `rejectNudge` + `rejectSubmission` path (`reject_nudge` column). No new tables.

**Tech Stack:** Existing Flutter app under `app/`, existing Supabase `chore_submissions.reject_nudge`, `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-29-encouragement-layer-v3.md` (locked; nits applied).

## Global Constraints

- Branch off **current `main` tip**. Do **not** branch from, rebase onto, or edit `feat/nebius-token-factory` / Nebius PR #3 three-beat work
- Open an implementation PR; **do not merge until Anoop greenlights**
- Basics demo video stays on hold separately; do not treat filming as a ship gate for this slice
- Kid screens remain **% only** (no `$`, no pocket, no parent save numbers)
- Reuse `reject_nudge` / `rejectNudge` / `rejectSubmission`; **no migration** unless a later task proves a real gap (none known)
- Pace = existing `GoalProgressView.kidBehindPace` → `isBehindPace` (do not invent a second formula)
- Kid-visible UI never uses: behind / missed / failed / overdue / rejected / try again (as failure)
- No em dashes in user-facing copy. No emoji. No designer-only “Slow week” chip
- Parent Approvals load-error button “Try again” stays (network retry, not a chore rejection)
- Parent Home “Behind pace” makeup card stays (parent-facing)
- TDD: failing test → implement → pass → commit per task
- Demo accounts stay `parent@demo` / `kid@demo` / `demo1234`
- Theme: `Dmc` Ledger tokens in `app/lib/core/dmc_theme.dart`

## File structure (touch)

```
app/lib/services/encouragement.dart                         # NEW pure copy + row/pace helpers
app/test/encouragement_test.dart                            # NEW
app/lib/features/kid/encouragement_widgets.dart             # NEW presentational
app/test/encouragement_widgets_test.dart                    # NEW
app/lib/features/parent/send_back_sheet.dart                # NEW
app/test/send_back_sheet_test.dart                          # NEW
app/lib/services/chore_service.dart                         # default rejectNudge string
app/lib/services/queries.dart                               # latestStatus + latestCreatedAt on KidChoreCard
app/lib/features/parent/approvals_screen.dart               # Send back + sheet
app/lib/features/kid/today_screen.dart                      # next try, sent, day-done, pace, hero, finale
app/lib/features/kid/mark_done_screen.dart                  # note eyebrow + after-send
app/test/overshoot_test.dart                                # retarget default nudge assertion
app/integration_test/demo_walkthrough_test.dart             # Send back / NEXT TRY
```

Do **not** add a Supabase migration. Do **not** edit Nebius files.

**Interfaces (locked for later tasks):**

```dart
enum KidRowKind { open, nextTry, sent }

KidRowKind kidRowKind({
  required String? latestStatus,
  required DateTime? latestAt,
  required String cadence,
  required DateTime now,
});

bool allSent(Iterable<KidRowKind> kinds);

double todayMovedPct({
  required List<({double weightPct, String cadence, DateTime? latestAt})> chores,
  required int weeksN,
  required DateTime now,
});

int checkInsToOnPace({
  required double progressPct,
  required int weeksN,
  required int weeksElapsed,
  required List<double> openCreditsDesc,
});

String kidHeroLine({required bool behindPace, required String goalMode});
String paceCardTitle(int checkIns);
String paceCardBody(List<String> openTitles);
String earnedHandOff({required String goalMode});
String rejectNudge({required String choreTitle, String? parentNote});
bool kidCopyAllowed(String s);
```

---

### Task 1: Pure encouragement math + copy

**Files:**
- Create: `app/lib/services/encouragement.dart`
- Create: `app/test/encouragement_test.dart`

**Interfaces:**
- Consumes: `expectedInstances`, `instanceCreditPct`, `isBehindPace` from `chore_progress_math.dart`
- Produces: the function signatures in the File structure block above (except `rejectNudge`, which stays in `chore_service.dart`)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/encouragement.dart';

void main() {
  final monday = DateTime(2026, 9, 28, 10); // Monday

  group('kidRowKind', () {
    test('no submission is open', () {
      expect(
        kidRowKind(latestStatus: null, latestAt: null, cadence: 'daily', now: monday),
        KidRowKind.open,
      );
    });

    test('rejected is next try', () {
      expect(
        kidRowKind(
          latestStatus: 'rejected',
          latestAt: monday,
          cadence: 'daily',
          now: monday,
        ),
        KidRowKind.nextTry,
      );
    });

    test('pending is sent', () {
      expect(
        kidRowKind(
          latestStatus: 'pending',
          latestAt: monday.subtract(const Duration(days: 2)),
          cadence: 'daily',
          now: monday,
        ),
        KidRowKind.sent,
      );
    });

    test('approved once is sent', () {
      expect(
        kidRowKind(
          latestStatus: 'approved',
          latestAt: DateTime(2026, 8, 1),
          cadence: 'once',
          now: monday,
        ),
        KidRowKind.sent,
      );
    });

    test('approved daily today is sent, yesterday is open', () {
      expect(
        kidRowKind(
          latestStatus: 'approved',
          latestAt: monday,
          cadence: 'daily',
          now: monday,
        ),
        KidRowKind.sent,
      );
      expect(
        kidRowKind(
          latestStatus: 'approved',
          latestAt: monday.subtract(const Duration(days: 1)),
          cadence: 'daily',
          now: monday,
        ),
        KidRowKind.open,
      );
    });

    test('approved weekly same ISO week is sent, prior week is open', () {
      expect(
        kidRowKind(
          latestStatus: 'approved',
          latestAt: DateTime(2026, 10, 3, 9), // Saturday of ISO week 40 (Mon 28 Sep). Sunday 27 Sep is week 39.
          cadence: 'weekly',
          now: monday,
        ),
        KidRowKind.sent,
      );
      expect(
        kidRowKind(
          latestStatus: 'approved',
          latestAt: DateTime(2026, 9, 20),
          cadence: 'weekly',
          now: monday,
        ),
        KidRowKind.open,
      );
    });
  });

  test('allSent is true only when every row is sent', () {
    expect(allSent([KidRowKind.sent, KidRowKind.sent]), isTrue);
    expect(allSent([KidRowKind.sent, KidRowKind.open]), isFalse);
    expect(allSent([KidRowKind.sent, KidRowKind.nextTry]), isFalse);
    expect(allSent(const []), isFalse);
  });

  test('todayMovedPct sums instance credits created today', () {
    // 14-week plan: bed 40/98 + dishes 30/98; laundry last week ignored
    final pct = todayMovedPct(
      chores: [
        (weightPct: 40.0, cadence: 'daily', latestAt: monday),
        (weightPct: 30.0, cadence: 'daily', latestAt: monday),
        (weightPct: 20.0, cadence: 'weekly', latestAt: DateTime(2026, 9, 20)),
      ],
      weeksN: 14,
      now: monday,
    );
    expect(pct, closeTo(40 / 98 + 30 / 98, 1e-9));
  });

  test('checkInsToOnPace counts greedy open credits', () {
    // 7 of 14 elapsed => expected 50; progress 40; gap 10
    // open credits 8 then 5 then 3 => two check-ins
    expect(
      checkInsToOnPace(
        progressPct: 40,
        weeksN: 14,
        weeksElapsed: 7,
        openCreditsDesc: [8, 5, 3],
      ),
      2,
    );
  });

  test('checkInsToOnPace is 0 when already on pace', () {
    expect(
      checkInsToOnPace(
        progressPct: 50,
        weeksN: 14,
        weeksElapsed: 7,
        openCreditsDesc: [8],
      ),
      0,
    );
  });

  group('copy', () {
    test('open hero never threatens the goal', () {
      expect(
        kidHeroLine(behindPace: false, goalMode: 'family_trip'),
        'Every check-in moves the bar.',
      );
    });

    test('slow hero keeps the trip put; kid_item uses reward', () {
      expect(
        kidHeroLine(behindPace: true, goalMode: 'family_trip'),
        'Every check-in moves it. The trip stays put.',
      );
      expect(
        kidHeroLine(behindPace: true, goalMode: 'kid_item'),
        'Every check-in moves it. The reward stays put.',
      );
    });

    test('pace card is path only', () {
      expect(
        paceCardTitle(2),
        'Two check-ins today puts the week back on pace.',
      );
      expect(
        paceCardTitle(1),
        'One check-in today puts the week back on pace.',
      );
      expect(
        paceCardBody(['Make your bed', 'Wash the dishes']),
        'Bed and dishes are right there - each one moves the bar.',
      );
      expect(paceCardTitle(2).toLowerCase(), isNot(contains('catch-up')));
      expect(paceCardBody(['Make your bed', 'Wash the dishes']).toLowerCase(),
          isNot(contains('lost ground')));
    });

    test('earned hand-off has no dollars', () {
      expect(earnedHandOff(goalMode: 'family_trip'),
          contains('talk about the trip together'));
      expect(earnedHandOff(goalMode: 'kid_item'), isNot(contains(r'$')));
      expect(kidCopyAllowed(earnedHandOff(goalMode: 'family_trip')), isTrue);
    });

    test('kidCopyAllowed bans failure words', () {
      expect(kidCopyAllowed('NEXT TRY'), isTrue);
      expect(kidCopyAllowed('A note from your parent'), isTrue);
      expect(kidCopyAllowed('Try again with a clearer photo'), isFalse);
      expect(kidCopyAllowed('You failed'), isFalse);
      expect(kidCopyAllowed('Behind pace'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/encouragement_test.dart`

Expected: FAIL compiling (`encouragement.dart` missing) or `kidRowKind` not defined.

- [ ] **Step 3: Write minimal implementation**

`app/lib/services/encouragement.dart`:

```dart
import 'chore_progress_math.dart';

enum KidRowKind { open, nextTry, sent }

const kKidBannedFragments = [
  'behind',
  'missed',
  'failed',
  'overdue',
  'rejected',
  'try again',
];

bool kidCopyAllowed(String s) {
  final lower = s.toLowerCase();
  return kKidBannedFragments.every((w) => !lower.contains(w));
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ISO week: Thursday-based week year + week number (DateTime.weekday Mon=1).
(int, int) _isoWeek(DateTime d) {
  final utc = DateTime.utc(d.year, d.month, d.day);
  final thursday = utc.add(Duration(days: 4 - utc.weekday));
  final firstThursday = DateTime.utc(thursday.year, 1, 4);
  final week = 1 + thursday.difference(firstThursday).inDays ~/ 7;
  return (thursday.year, week);
}

KidRowKind kidRowKind({
  required String? latestStatus,
  required DateTime? latestAt,
  required String cadence,
  required DateTime now,
}) {
  if (latestStatus == 'rejected') return KidRowKind.nextTry;
  if (latestStatus == 'pending') return KidRowKind.sent;
  if (latestStatus == 'approved' && latestAt != null) {
    if (cadence == 'once') return KidRowKind.sent;
    if (cadence == 'daily') {
      return _sameCalendarDay(latestAt, now) ? KidRowKind.sent : KidRowKind.open;
    }
    if (cadence == 'weekly') {
      return _isoWeek(latestAt) == _isoWeek(now)
          ? KidRowKind.sent
          : KidRowKind.open;
    }
  }
  return KidRowKind.open;
}

bool allSent(Iterable<KidRowKind> kinds) {
  final list = kinds.toList();
  if (list.isEmpty) return false;
  return list.every((k) => k == KidRowKind.sent);
}

double todayMovedPct({
  required List<({double weightPct, String cadence, DateTime? latestAt})> chores,
  required int weeksN,
  required DateTime now,
}) {
  var total = 0.0;
  for (final c in chores) {
    final at = c.latestAt;
    if (at == null || !_sameCalendarDay(at, now)) continue;
    final expected = expectedInstances(cadence: c.cadence, weeksN: weeksN);
    total += instanceCreditPct(
        weightPct: c.weightPct, expectedInstances: expected);
  }
  return total;
}

int checkInsToOnPace({
  required double progressPct,
  required int weeksN,
  required int weeksElapsed,
  required List<double> openCreditsDesc,
}) {
  if (!isBehindPace(
    progressPct: progressPct,
    weeksN: weeksN,
    weeksElapsed: weeksElapsed,
    planWeightSum: 100,
  )) {
    return 0;
  }
  final n = weeksN < 1 ? 1 : weeksN;
  final elapsed = weeksElapsed.clamp(0, n);
  final gap = 100.0 * elapsed / n - progressPct;
  var acc = 0.0;
  var count = 0;
  for (final credit in openCreditsDesc) {
    if (acc + 1e-6 >= gap) break;
    acc += credit;
    count += 1;
  }
  return count;
}

String kidHeroLine({required bool behindPace, required String goalMode}) {
  if (!behindPace) return 'Every check-in moves the bar.';
  final noun = goalMode == 'family_trip' ? 'trip' : 'reward';
  return 'Every check-in moves it. The $noun stays put.';
}

const _ones = {
  1: 'One',
  2: 'Two',
  3: 'Three',
  4: 'Four',
  5: 'Five',
  6: 'Six',
  7: 'Seven',
  8: 'Eight',
  9: 'Nine',
  10: 'Ten',
};

String paceCardTitle(int checkIns) {
  if (checkIns <= 0) return 'Each check-in today moves the bar.';
  final word = _ones[checkIns] ?? '$checkIns';
  final noun = checkIns == 1 ? 'check-in' : 'check-ins';
  final verb = checkIns == 1 ? 'puts' : 'puts';
  // ponytail: English verb stays "puts" for the locked 1/2-check-in copy.
  return '$word $noun today $verb the week back on pace.';
}

String _shortChoreName(String title) {
  final t = title.trim().toLowerCase();
  const prefixes = [
    'make your ',
    'wash the ',
    'fold the ',
    'plan the ',
  ];
  for (final p in prefixes) {
    if (t.startsWith(p)) {
      final rest = t.substring(p.length);
      return rest.split(RegExp(r'\s+')).first;
    }
  }
  return t.split(RegExp(r'\s+')).last;
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String paceCardBody(List<String> openTitles) {
  if (openTitles.isEmpty) return 'Each check-in moves the bar.';
  final names = openTitles.map(_shortChoreName).toList();
  if (names.length == 1) {
    return '${_cap(names[0])} is right there - it moves the bar.';
  }
  if (names.length == 2) {
    return '${_cap(names[0])} and ${names[1]} are right there - each one moves the bar.';
  }
  return '${_cap(names[0])}, ${names[1]}, and more are right there - each one moves the bar.';
}

String earnedHandOff({required String goalMode}) {
  if (goalMode == 'family_trip') {
    return 'Every habit, all the way here. Your parent takes it from here - talk about the trip together tonight.';
  }
  return 'Every habit, all the way here. Your parent takes it from here - talk about it together tonight.';
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `cd app && flutter test test/encouragement_test.dart`

Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/encouragement.dart app/test/encouragement_test.dart
git commit -m "feat(v3): encouragement row-kind, pace copy, and today % helpers"
```

---

### Task 2: Kind default `rejectNudge`

**Files:**
- Modify: `app/lib/services/chore_service.dart` (`rejectNudge`, ~lines 22-28)
- Modify: `app/test/overshoot_test.dart` (group `reject builds a nudge`, ~lines 46-50)
- Test: `app/test/overshoot_test.dart`, `app/test/encouragement_test.dart` (add a case if you re-export)

**Interfaces:**
- Consumes: existing `rejectNudge({required String choreTitle, String? parentNote})`
- Produces: same signature; default string is the locked photo-tip (no “Try again”)

- [ ] **Step 1: Write the failing assertion**

Replace the existing test in `app/test/overshoot_test.dart`:

```dart
    test('reject builds a nudge and returns chore to Today', () {
      final nudge = rejectNudge(choreTitle: 'Wash the dishes');
      expect(nudge, isNotEmpty);
      expect(nudge.toLowerCase(), isNot(contains('try again')));
      expect(nudge, contains('bright light'));
      expect(nudge, contains('Wash the dishes'));
      expect(kidCopyAllowed(nudge), isTrue);
    });

    test('reject prefers a non-empty parent note', () {
      expect(
        rejectNudge(choreTitle: 'Bed', parentNote: '  Whole sheet, please.  '),
        'Whole sheet, please.',
      );
      expect(
        rejectNudge(choreTitle: 'Bed', parentNote: '   '),
        rejectNudge(choreTitle: 'Bed'),
      );
    });
```

Add `import 'package:do_my_chore/services/encouragement.dart';` at the top of `overshoot_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/overshoot_test.dart --name "reject builds"`

Expected: FAIL — default still contains “try again”.

- [ ] **Step 3: Write minimal implementation**

In `app/lib/services/chore_service.dart`, replace the default return:

```dart
String rejectNudge({required String choreTitle, String? parentNote}) {
  if (parentNote != null && parentNote.trim().isNotEmpty) {
    return parentNote.trim();
  }
  return 'So close! One more photo of the whole "$choreTitle" - bright light if you can - and this one\'s done.';
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `cd app && flutter test test/overshoot_test.dart test/encouragement_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/chore_service.dart app/test/overshoot_test.dart
git commit -m "feat(v3): kind default reject nudge without try-again"
```

---

### Task 3: Expose latest submission on `KidChoreCard`

**Files:**
- Modify: `app/lib/services/queries.dart` (`KidChoreCard` + `todayForKid`)
- Test: `app/test/encouragement_test.dart` (keep using the pure `kidRowKind` inputs; this task is wiring)

**Interfaces:**
- Consumes: `todayForKid` already selects `chore_submissions(status, reject_nudge, created_at)`
- Produces:

```dart
class KidChoreCard {
  // existing fields...
  final String? latestStatus; // pending | approved | rejected | null
  final DateTime? latestCreatedAt;

  KidRowKind rowKind(DateTime now) => kidRowKind(
        latestStatus: latestStatus,
        latestAt: latestCreatedAt,
        cadence: cadence,
        now: now,
      );
}
```

- [ ] **Step 1: Add fields with defaults so the existing const constructor still compiles**

Import `encouragement.dart` from `queries.dart`. Then add:

```dart
  final String? latestStatus;
  final DateTime? latestCreatedAt;

  const KidChoreCard({
    required this.id,
    required this.title,
    required this.cadence,
    required this.weightPct,
    required this.requiresPhoto,
    required this.isMakeup,
    required this.isBonus,
    this.nudge,
    this.latestStatus,
    this.latestCreatedAt,
  });

  KidRowKind rowKind(DateTime now) => kidRowKind(
        latestStatus: latestStatus,
        latestAt: latestCreatedAt,
        cadence: cadence,
        now: now,
      );
```

In `todayForKid`, after sorting `subs` newest first:

```dart
      String? nudge;
      String? latestStatus;
      DateTime? latestCreatedAt;
      if (subs.isNotEmpty) {
        final sorted = [...subs]
          ..sort((a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String));
        final latest = sorted.first;
        latestStatus = latest['status'] as String?;
        final created = latest['created_at'] as String?;
        if (created != null) latestCreatedAt = DateTime.parse(created);
        if (latestStatus == 'rejected') {
          nudge = latest['reject_nudge'] as String?;
        }
      }
      return KidChoreCard(
        // existing mappings...
        nudge: nudge,
        latestStatus: latestStatus,
        latestCreatedAt: latestCreatedAt,
      );
```

- [ ] **Step 2: Add one mapper unit test** (no Supabase)

Append to `app/test/encouragement_test.dart`:

```dart
  test('KidChoreCard.rowKind uses latest fields', () {
    final card = KidChoreCard(
      id: 'c1',
      title: 'Make your bed',
      cadence: 'daily',
      weightPct: 40,
      requiresPhoto: true,
      isMakeup: false,
      isBonus: false,
      latestStatus: 'pending',
      latestCreatedAt: DateTime(2026, 9, 28),
    );
    expect(card.rowKind(DateTime(2026, 9, 28)), KidRowKind.sent);
  });
```

- [ ] **Step 3: Run tests**

Run: `cd app && flutter test test/encouragement_test.dart test/overshoot_test.dart`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/queries.dart app/test/encouragement_test.dart
git commit -m "feat(v3): surface latest submission status on kid chore cards"
```

---

### Task 4: Presentational kid widgets

**Files:**
- Create: `app/lib/features/kid/encouragement_widgets.dart`
- Create: `app/test/encouragement_widgets_test.dart`

**Interfaces:**
- Consumes: copy strings from Task 1; `Dmc` tokens
- Produces: `KidNextTryNote`, `KidNextTryBadge`, `KidSentChip`, `KidDayDoneCard`, `KidPaceCard`, `KidSentConfirmation`, `KidGoalEarnedFinale`

- [ ] **Step 1: Write failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/kid/encouragement_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('next-try note uses parent eyebrow, not PARENT SAID', (tester) async {
    await tester.pumpWidget(_wrap(const KidNextTryNote(note: 'Whole bed, bright light.')));
    expect(find.text('A note from your parent'), findsOneWidget);
    expect(find.text('PARENT SAID'), findsNothing);
    expect(find.text('Whole bed, bright light.'), findsOneWidget);
    expect(find.textContaining('Try again'), findsNothing);
  });

  testWidgets('badge says NEXT TRY', (tester) async {
    await tester.pumpWidget(_wrap(const KidNextTryBadge()));
    expect(find.text('NEXT TRY'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
  });

  testWidgets('day-done card names the percent chip and keeps copy calm', (tester) async {
    await tester.pumpWidget(_wrap(const KidDayDoneCard(movedPct: 0.714)));
    expect(find.text("That's today done."), findsOneWidget);
    expect(find.textContaining('moved the bar today'), findsOneWidget);
    expect(find.textContaining('+0.7%'), findsOneWidget);
  });

  testWidgets('day-done skips confetti when animations are disabled', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _wrap(const KidDayDoneCard(movedPct: 1.2)),
    ));
    await tester.pump();
    expect(find.byKey(const Key('dmc-confetti')), findsNothing);
  });

  testWidgets('pace card is path copy only', (tester) async {
    await tester.pumpWidget(_wrap(KidPaceCard(
      title: paceTitle,
      body: paceBody,
    )));
    expect(find.text(paceTitle), findsOneWidget);
    expect(find.text(paceBody), findsOneWidget);
    expect(find.textContaining('Slow week'), findsNothing);
    expect(find.textContaining('catch-up'), findsNothing);
  });

  testWidgets('sent confirmation copy', (tester) async {
    await tester.pumpWidget(_wrap(KidSentConfirmation(onBack: () {})));
    expect(find.text('Sent to your parent.'), findsOneWidget);
    expect(
      find.text('The bar moves the moment they take a look.'),
      findsOneWidget,
    );
    expect(find.text('Back to today'), findsOneWidget);
  });

  testWidgets('finale has no dollars', (tester) async {
    await tester.pumpWidget(_wrap(const KidGoalEarnedFinale(
      goalTitle: 'Disneyland',
      handOff: 'Your parent takes it from here - talk about the trip together tonight.',
    )));
    expect(find.text('You earned it.'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('Disneyland'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });
}

const paceTitle = 'Two check-ins today puts the week back on pace.';
const paceBody = 'Bed and dishes are right there - each one moves the bar.';
```

- [ ] **Step 2: Run tests — expect FAIL** (library missing)

Run: `cd app && flutter test test/encouragement_widgets_test.dart`

- [ ] **Step 3: Implement the widgets**

Keep them dumb: `Dmc.marigoldSoft` / `Dmc.cream` / `Dmc.pineSoft` cards matching the V3 mock. Rules:

- `KidNextTryNote`: eyebrow `A note from your parent` (`Dmc.micro` + `Dmc.marigoldDeep`), body is the raw note.
- `KidNextTryBadge`: text `NEXT TRY`.
- `KidSentChip`: text `Sent - waiting for your parent` (hyphen, not em dash).
- `KidDayDoneCard`: title `That's today done.`; chip `+{movedPct.toStringAsFixed(1)}%` + `moved the bar today`; subtitle `Parent checks the photos, then it counts. New chores land tomorrow.`; confetti (`Key('dmc-confetti')`) only when `!MediaQuery.of(context).disableAnimations`.
- `KidPaceCard`: cream row, title + body passed in. No chip labeled Slow week.
- `KidSentConfirmation`: pine ring, titles from spec, `Back to today` calls `onBack`.
- `KidGoalEarnedFinale`: full-bleed `Image.asset('assets/photos/castle.jpg')`, `100%`, `You earned it.`, `handOff`, goal title chip. No `$`.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd app && flutter test test/encouragement_widgets_test.dart`

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/kid/encouragement_widgets.dart app/test/encouragement_widgets_test.dart
git commit -m "feat(v3): kid encouragement presentational widgets"
```

---

### Task 5: Parent Send back sheet

**Files:**
- Create: `app/lib/features/parent/send_back_sheet.dart`
- Create: `app/test/send_back_sheet_test.dart`
- Modify: `app/lib/features/parent/approvals_screen.dart` (`_reject`, button label ~287)

**Interfaces:**
- Consumes: `rejectNudge`, `rejectSubmission`
- Produces: `SendBackSheet` with `initialNote`, `onConfirm(String note)`, live preview

- [ ] **Step 1: Write failing widget tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/parent/send_back_sheet.dart';
import 'package:do_my_chore/services/chore_service.dart';

void main() {
  testWidgets('preview tracks the textarea and matches kid eyebrow', (tester) async {
    String? confirmed;
    final initial = rejectNudge(choreTitle: 'Make your bed');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendBackSheet(
          kidName: 'Arjun',
          initialNote: initial,
          onCancel: () {},
          onConfirm: (n) => confirmed = n,
        ),
      ),
    ));
    expect(find.text('Send back with a note'), findsOneWidget);
    expect(find.text('A note from your parent'), findsOneWidget);
    expect(find.text(initial), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Whole sheet in the frame.');
    await tester.pump();
    expect(find.text('Whole sheet in the frame.'), findsWidgets);
    await tester.tap(find.text('Send note'));
    expect(confirmed, 'Whole sheet in the frame.');
  });

  testWidgets('blank note confirms as the kind default', (tester) async {
    String? confirmed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendBackSheet(
          kidName: 'Arjun',
          initialNote: rejectNudge(choreTitle: 'Make your bed'),
          onCancel: () {},
          onConfirm: (n) => confirmed = n,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Send note'));
    expect(confirmed, rejectNudge(choreTitle: 'Make your bed'));
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd app && flutter test test/send_back_sheet_test.dart`

- [ ] **Step 3: Implement `SendBackSheet` + wire Approvals**

Sheet UI (from mock, nits already applied):

- Title: `Send back with a note`
- Sub: `{kidName} sees this as a friendly next try - never a rejection on his screen.`
- `TextField` (multiline) seeded with `initialNote`
- Preview card: micro `{kidName} will see` + `A note from your parent` + live quote
- Buttons: `Keep it` → `onCancel`; `Send note` → `onConfirm(rejectNudge(choreTitle: choreTitle, parentNote: controller.text))`

In `approvals_screen.dart`:

- Button label: `Send back` (replace `Reject with nudge`).
- `_reject` becomes: open `showModalBottomSheet` (`isScrollControlled: true`) with `SendBackSheet`. On confirm only, call `rejectNudge(choreTitle: p.choreTitle, parentNote: note)` then `rejectSubmission`. On cancel, do not mark `_decided`.
- Success snackbar: `Sent back to Arjun with a note.` (no “try again”).

POC: keep hardcoded `Arjun` (existing Approvals already says `SUBMITTED BY ARJUN`).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/send_back_sheet_test.dart test/overshoot_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/parent/send_back_sheet.dart app/test/send_back_sheet_test.dart app/lib/features/parent/approvals_screen.dart
git commit -m "feat(v3): Send back sheet with live kid preview"
```

---

### Task 6: Wire Kid Today

**Files:**
- Modify: `app/lib/features/kid/today_screen.dart`
- Test: `app/test/encouragement_widgets_test.dart` (add a `KidTodayBody` pump) or new `app/test/kid_today_encouragement_test.dart`

**Interfaces:**
- Consumes: `KidChoreCard.rowKind`, `allSent`, `todayMovedPct`, `kidHeroLine`, `paceCardTitle`, `paceCardBody`, `checkInsToOnPace`, `GoalProgressView.kidBehindPace`, widgets from Task 4
- Produces: `KidTodayBody` taking `chores`, `goals`, `now` so tests do not need Supabase

- [ ] **Step 1: Extract `KidTodayBody` and write a failing widget test**

```dart
testWidgets('Today shows next try, hides try-again, keeps sent rows', (tester) async {
  final now = DateTime(2026, 9, 28, 10);
  final chores = [
    KidChoreCard(
      id: 'c1',
      title: 'Make your bed',
      cadence: 'daily',
      weightPct: 40,
      requiresPhoto: true,
      isMakeup: false,
      isBonus: false,
      latestStatus: 'pending',
      latestCreatedAt: now,
    ),
    KidChoreCard(
      id: 'c2',
      title: 'Wash the dishes',
      cadence: 'daily',
      weightPct: 30,
      requiresPhoto: true,
      isMakeup: false,
      isBonus: false,
      nudge: 'Whole sink, bright light.',
      latestStatus: 'rejected',
      latestCreatedAt: now,
    ),
  ];
  final goal = GoalProgressView(
    id: 'g1',
    title: 'Disneyland',
    targetAmount: 3500,
    goalMode: 'family_trip',
    allowMakeup: false,
    targetDate: now.add(const Duration(days: 70)),
    weeksN: 14,
    weeksElapsed: 0,
    choreProgressPct: 23,
    parentSaved: 0,
    planWeightSum: 100,
    weeklyParentSave: 250,
  );
  await tester.pumpWidget(MaterialApp(
    home: KidTodayBody(chores: chores, goals: [goal], now: now, onOpen: (_) {}),
  ));
  expect(find.text('NEXT TRY'), findsOneWidget);
  expect(find.text('TRY AGAIN'), findsNothing);
  expect(find.textContaining('Try again'), findsNothing);
  expect(find.text('Whole sink, bright light.'), findsOneWidget);
  expect(find.text('Sent - waiting for your parent'), findsOneWidget);
  expect(find.text('Every check-in moves the bar.'), findsOneWidget);
  expect(find.textContaining('100% earns'), findsNothing);
});
```

Add a second test: `weeksElapsed: 7`, `choreProgressPct: 20`, both chores `open` → finds pace title/body, finds slow hero, finds no `Slow week`.

Add a third test: both chores `pending` → finds `That's today done.`, finds both sent chips, finds no pace card.

- [ ] **Step 2: Run — expect FAIL** (`KidTodayBody` missing)

- [ ] **Step 3: Implement Today wiring**

In `KidTodayBody.build`:

1. If any goal `choreProgressPct >= 100 - 1e-9`, render `KidGoalEarnedFinale` (Task 8 can finish the asset polish; a placeholder that already shows “You earned it.” is OK here if Task 8 is next — **prefer calling `KidGoalEarnedFinale` now** so this test can assert it).
2. Else show existing hero + rail. Hero line = `kidHeroLine(behindPace: g.kidBehindPace, goalMode: g.goalMode)` — **never** “Keep the habits going. 100% earns the trip.”
3. Compute `kinds = chores.map((c) => c.rowKind(now))`.
4. If `allSent(kinds)`: insert `KidDayDoneCard(movedPct: todayMovedPct(...))` above the list. Keep every row, each with `KidSentChip`. Rows are not tappable.
5. Else if `g.kidBehindPace` and any kind is `open`: insert `KidPaceCard` with `paceCardTitle(checkInsToOnPace(...))` and `paceCardBody(openTitles)`. `openCreditsDesc` = instance credits of `open` chores, sorted descending.
6. `nextTry` rows: `KidNextTryNote` + `KidNextTryBadge`; tappable → Mark Done.
7. `open` rows: existing tap → Mark Done.
8. `sent` rows: pine-soft background, `KidSentChip`, **no** Navigator push.

`KidTodayScreen` loads as today, then `KidTodayBody(chores: _chores, goals: _goals, now: DateTime.now(), ...)`.

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/encouragement_widgets_test.dart test/kid_today_encouragement_test.dart test/encouragement_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/kid/today_screen.dart app/test/kid_today_encouragement_test.dart
git commit -m "feat(v3): kid Today next-try, sent rows, day-done, and pace card"
```

---

### Task 7: Mark Done note + after-send

**Files:**
- Modify: `app/lib/features/kid/mark_done_screen.dart`
- Create: `app/test/mark_done_encouragement_test.dart`

**Interfaces:**
- Consumes: `KidNextTryNote`, `KidSentConfirmation`
- Produces: after successful `uploadAndSubmit` / `submitChore`, set `_sent = true` instead of `Navigator.pop`

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('retry uses A note from your parent', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: MarkDoneScreen(
      service: _FakeChoreService(),
      chore: KidChoreCard(
        id: 'c1',
        title: 'Make your bed',
        cadence: 'daily',
        weightPct: 40,
        requiresPhoto: false,
        isMakeup: false,
        isBonus: false,
        nudge: 'Whole bed, bright light.',
      ),
      weeksN: 14,
    ),
  ));
  expect(find.text('A note from your parent'), findsOneWidget);
  expect(find.text('PARENT SAID'), findsNothing);
  expect(find.text('Whole bed, bright light.'), findsOneWidget);
});
```

`_FakeChoreService` can be a tiny `Fake` / hand-rolled subclass only if `ChoreService` is hard to fake. Prefer extracting the note + sent views so the sent test pumps `KidSentConfirmation` (already covered) and this test pumps Mark Done with `choreService` nullable-unsafe.

If constructing `ChoreService` is painful, split a `MarkDoneView` that takes `onSubmit` / `sent` flags — keep it in `mark_done_screen.dart`.

Second test: tap `Done! Send to parent` on a non-photo chore → finds `Sent to your parent.` and does **not** pop the route (use a `Navigator` observer or expect the sent title on the same route).

- [ ] **Step 2: Run — expect FAIL** (`PARENT SAID` still there; submit pops)

- [ ] **Step 3: Implement**

- Replace the `PARENT SAID` block with `KidNextTryNote(note: chore.nudge!)`.
- On success: `setState(() => _sent = true)` — do not pop.
- When `_sent`: body is `KidSentConfirmation(onBack: () => Navigator.pop(context))`.
- Align photo-attached line with mock if touched: `Photo attached - it counts once your parent takes a look.` (only if you are already in that widget; do not drive-by rewrite other strings).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/mark_done_encouragement_test.dart test/encouragement_widgets_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/kid/mark_done_screen.dart app/test/mark_done_encouragement_test.dart
git commit -m "feat(v3): parent note eyebrow and after-send confirmation"
```

---

### Task 8: Goal 100% finale

**Files:**
- Modify: `app/lib/features/kid/today_screen.dart` (if Task 6 left a stub)
- Modify: `app/lib/features/kid/encouragement_widgets.dart` (`KidGoalEarnedFinale`)
- Test: `app/test/kid_today_encouragement_test.dart`

**Interfaces:**
- Consumes: `earnedHandOff(goalMode:)`, `assets/photos/castle.jpg` (no goal cover column)
- Produces: Today body is the finale when `choreProgressPct >= 100 - 1e-9`

- [ ] **Step 1: Failing test** — `GoalProgressView` with `choreProgressPct: 100` finds `You earned it.`, `100%`, hand-off containing `talk about the trip`, finds no `$`, finds no Today chore list.

- [ ] **Step 2: Run — expect FAIL** if finale is not yet the only body.

- [ ] **Step 3: Implement** — when earned, return `KidGoalEarnedFinale` as the scroll body (hero image = existing castle asset). Do not show the pace card or day-done card on top of it.

- [ ] **Step 4: Run** `cd app && flutter test test/kid_today_encouragement_test.dart test/encouragement_widgets_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/kid/today_screen.dart app/lib/features/kid/encouragement_widgets.dart app/test/kid_today_encouragement_test.dart
git commit -m "feat(v3): full-screen 100% earned finale"
```

---

### Task 9: Walkthrough + copy audit

**Files:**
- Modify: `app/integration_test/demo_walkthrough_test.dart` (beat 8, ~lines 142-157)
- Optional: `app/test/encouragement_test.dart` (collect every kid-visible literal used in widgets and assert `kidCopyAllowed`)

**Interfaces:**
- Consumes: new button/label strings
- Produces: walkthrough still films reject → kid retry

- [ ] **Step 1: Update walkthrough finders**

```dart
    final reject = find.text('Send back');
    expect(reject, findsWidgets);
    await tester.tap(reject.first);
    await _settle(tester, 800);
    await tester.tap(find.text('Send note'));
    await _settle(tester, 1500);
    // ... existing pop back to shell ...
    await tester.tap(find.text('Kid'));
    await _settle(tester, 1500);
    expect(find.text('NEXT TRY'), findsWidgets);
    expect(find.textContaining('Try again'), findsNothing);
```

- [ ] **Step 2: Static copy audit test**

```dart
  test('locked kid literals pass the ban list', () {
    const literals = [
      'NEXT TRY',
      'A note from your parent',
      "That's today done.",
      'moved the bar today',
      'Sent - waiting for your parent',
      'Sent to your parent.',
      'The bar moves the moment they take a look.',
      'Every check-in moves the bar.',
      'Every check-in moves it. The trip stays put.',
      'Two check-ins today puts the week back on pace.',
      'Bed and dishes are right there - each one moves the bar.',
      'You earned it.',
    ];
    for (final s in literals) {
      expect(kidCopyAllowed(s), isTrue, reason: s);
      expect(s.contains('—'), isFalse, reason: s); // no em dash
    }
  });
```

- [ ] **Step 3: Run unit/widget suite**

Run: `cd app && flutter test`

Expected: PASS. Integration test needs the simulator + local Supabase; run when the demo machine is up:

`cd app && flutter test integration_test/demo_walkthrough_test.dart`

- [ ] **Step 4: Grep kid UI for leftover failure words**

Run: `rg -n "TRY AGAIN|PARENT SAID|Try again -|Reject with nudge|100% earns the" app/lib/features/kid app/lib/features/parent/approvals_screen.dart app/lib/services/chore_service.dart`

Expected: no matches except comments / parent load-error “Try again”.

- [ ] **Step 5: Commit**

```bash
git add app/integration_test/demo_walkthrough_test.dart app/test/encouragement_test.dart
git commit -m "test(v3): walkthrough Send back and kid copy audit"
```

---

### Task 10: Ship gate (human)

**Files:** none (process only)

- [ ] **Step 1:** Confirm the implementation branch was cut from `main` (not `feat/nebius-token-factory`) and the diff does not include Nebius / token-factory files.

- [ ] **Step 2:** Open or update the implementation PR. Title example: `feat: V3 encouragement layer`. Body: three beats (next try / celebration / soft pace) + nits + “no schema change; `reject_nudge` reused”.

- [ ] **Step 3:** **Do not merge** until Anoop greenlights. Basics demo video remains on hold separately.

- [ ] **Step 4:** No commit required for this task.

---

## Self-review

1. **Spec coverage**
   - §2.1 next try + Send back sheet → Tasks 2, 4, 5, 6, 7
   - §2.2 day-done, after-send, 100% finale → Tasks 4, 6, 7, 8
   - §2.3 pace + open hero → Tasks 1, 6
   - §2.4 copy rules → Tasks 1, 2, 9
   - §3 non-goals / Nebius / no merge → Global Constraints + Task 10
   - §4 row states → Tasks 1, 3, 6
   - §5 schema reuse → no migration task (intentional)
2. **Placeholder scan:** no TBD / “handle edge cases” / “similar to Task N”.
3. **Type consistency:** `KidRowKind`, `kidRowKind`, `allSent`, `todayMovedPct`, `checkInsToOnPace`, `kidHeroLine`, `paceCardTitle`, `paceCardBody`, `earnedHandOff`, `KidChoreCard.latestStatus` / `latestCreatedAt` are named the same in Tasks 1–8.
4. **Mock vs nits:** mock “Slow week”, “Keep the habits going. 100% earns the trip.”, “No catch-up pile, no lost ground.”, “+5.7%”, “PARENT SAID”, “TRY AGAIN”, “Reject with nudge” are all overridden by the spec.
