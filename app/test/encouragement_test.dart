import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/encouragement.dart';
import 'package:do_my_chore/services/queries.dart';

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
          // Saturday of ISO week 40 (Mon 28 Sep 2026). Sunday 27 Sep is week 39.
          latestAt: DateTime(2026, 10, 3, 9),
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

    test('parent Home rail cap is path, not pressure', () {
      expect(parentRailRightCap(), 'path to 100%');
      expect(parentRailRightCap().toLowerCase(), isNot(contains('earns')));
      expect(parentRailRightCap().contains('\u2014'), isFalse);
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
      expect(
          paceCardBody(['Make your bed', 'Wash the dishes']).toLowerCase(),
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
        expect(s.contains('\u2014'), isFalse, reason: s);
      }
    });
  });

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
}
