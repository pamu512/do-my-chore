import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/chore_progress_math.dart';

void main() {
  group('weeksRemaining', () {
    test('ceils days over 7, minimum 1', () {
      final today = DateTime(2026, 9, 27);
      expect(weeksRemaining(today: today, targetDate: DateTime(2026, 10, 4)), 1);
      expect(weeksRemaining(today: today, targetDate: DateTime(2026, 10, 5)), 2);
      expect(weeksRemaining(today: today, targetDate: DateTime(2026, 12, 27)), 13);
      expect(
          weeksRemaining(
              today: today, targetDate: today.subtract(const Duration(days: 3))),
          1);
    });
  });

  group('expectedInstances', () {
    test('once is 1, weekly is N, daily is 7*N', () {
      expect(expectedInstances(cadence: 'once', weeksN: 14), 1);
      expect(expectedInstances(cadence: 'weekly', weeksN: 14), 14);
      expect(expectedInstances(cadence: 'daily', weeksN: 14), 98);
    });

    test('N below 1 is clamped to 1', () {
      expect(expectedInstances(cadence: 'daily', weeksN: 0), 7);
      expect(expectedInstances(cadence: 'weekly', weeksN: -3), 1);
    });
  });

  group('instanceCreditPct', () {
    test('daily credit is weight / (7*N)', () {
      expect(
          instanceCreditPct(weightPct: 40, expectedInstances: 98),
          closeTo(40 / 98, 1e-9));
    });

    test('once credit is full weight', () {
      expect(instanceCreditPct(weightPct: 10, expectedInstances: 1), 10);
    });
  });

  group('kidProgressPct', () {
    test('Disneyland perfect streak hits 100', () {
      final n = 14;
      final chores = [
        (weightPct: 40.0, cadence: 'daily', approvedCount: 7 * n),
        (weightPct: 30.0, cadence: 'daily', approvedCount: 7 * n),
        (weightPct: 20.0, cadence: 'weekly', approvedCount: n),
        (weightPct: 10.0, cadence: 'once', approvedCount: 1),
      ];
      expect(kidProgressPct(chores: chores, weeksN: n), 100);
    });

    test('kid bar caps at 100 when oversubscribed', () {
      final n = 6;
      final chores = [
        (weightPct: 80.0, cadence: 'once', approvedCount: 1),
        (weightPct: 50.0, cadence: 'once', approvedCount: 1),
      ];
      expect(kidProgressPct(chores: chores, weeksN: n), 100);
    });

    test('partial progress sums fractionally', () {
      final chores = [
        (weightPct: 40.0, cadence: 'daily', approvedCount: 14),
        (weightPct: 10.0, cadence: 'once', approvedCount: 0),
      ];
      // 40 * 14/98 = 5.714...
      expect(
          kidProgressPct(chores: chores, weeksN: 14), closeTo(40 * 14 / 98, 1e-9));
    });

    test('approvedCount above expected instances does not overshoot a chore',
        () {
      final chores = [
        (weightPct: 40.0, cadence: 'daily', approvedCount: 200),
      ];
      // capped per-chore at its full weight, not 40 * 200/98
      expect(kidProgressPct(chores: chores, weeksN: 14), 40);
    });
  });

  group('isBehindPace', () {
    test('on pace when progress matches elapsed share of plan weight', () {
      // plan weight 100, 7 of 14 weeks elapsed, progress 50 -> on pace
      expect(
          isBehindPace(
              progressPct: 50,
              weeksN: 14,
              weeksElapsed: 7,
              planWeightSum: 100),
          isFalse);
    });

    test('behind pace when progress lags elapsed share', () {
      expect(
          isBehindPace(
              progressPct: 20,
              weeksN: 14,
              weeksElapsed: 7,
              planWeightSum: 100),
          isTrue);
    });

    test('oversubscribed slack: on pace while projection still reaches 100', () {
      // 60% at half time on a 130% plan projects to 120%: on pace.
      expect(
          isBehindPace(
              progressPct: 60,
              weeksN: 14,
              weeksElapsed: 7,
              planWeightSum: 130),
          isFalse);
      // 45% at half time on the same plan projects to 90%: behind.
      expect(
          isBehindPace(
              progressPct: 45,
              weeksN: 14,
              weeksElapsed: 7,
              planWeightSum: 130),
          isTrue);
    });

    test('clamp guards: elapsed > N or zero weeks', () {
      // At/after the deadline the expected pace is 100: half-funded is behind.
      expect(
          isBehindPace(
              progressPct: 50,
              weeksN: 14,
              weeksElapsed: 20,
              planWeightSum: 100),
          isTrue);
      expect(
          isBehindPace(
              progressPct: 0, weeksN: 14, weeksElapsed: 0, planWeightSum: 100),
          isFalse); // 0 >= 0
      expect(
          isBehindPace(
              progressPct: 10, weeksN: 0, weeksElapsed: 5, planWeightSum: 100),
          isTrue); // weeksN clamps to 1 -> expected 100 -> 10 < 100
    });
  });

  group('randomBonusWeightPct (stretch helper, stubbed band)', () {
    test('always lands on a discrete slot 3/5/8/10/12', () {
      final rng = Random(42);
      for (var i = 0; i < 50; i++) {
        expect([3, 5, 8, 10, 12], contains(randomBonusWeightPct(rng)));
      }
    });
  });
}
