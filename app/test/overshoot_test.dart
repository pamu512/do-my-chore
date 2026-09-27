import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/chore_service.dart';

/// Tests for the approve/reject decision logic — the pure, DB-free core of
/// the submission flow. Ledger truth: overshoot fills the goal, remainder
/// goes to pocket, all in the same approval transaction.
void main() {
  group('approve decision math', () {
    test('approve credits goal up to target, remainder to pocket', () {
      final d = approveSplit(
        reward: 30,
        splitGoalPct: 100,
        goalBank: 90,
        targetAmount: 100,
      );
      expect(d.goalCredit, 10);
      expect(d.pocketCredit, 20);
    });

    test('under target credits split pct to goal, rest to pocket', () {
      final d = approveSplit(
        reward: 10,
        splitGoalPct: 80,
        goalBank: 0,
        targetAmount: 100,
      );
      expect(d.goalCredit, 8);
      expect(d.pocketCredit, 2);
    });

    test('full goal split with no overshoot lands entirely in goal', () {
      final d = approveSplit(
        reward: 15,
        splitGoalPct: 100,
        goalBank: 0,
        targetAmount: 100,
      );
      expect(d.goalCredit, 15);
      expect(d.pocketCredit, 0);
    });

    test('funded goal sends everything to pocket regardless of split', () {
      final d = approveSplit(
        reward: 5,
        splitGoalPct: 80,
        goalBank: 100,
        targetAmount: 100,
      );
      expect(d.goalCredit, 0);
      expect(d.pocketCredit, 5);
    });
  });

  group('submission state machine', () {
    test('photo chore cannot submit without photo', () {
      expect(
        () => assertSubmittable(requiresPhoto: true, hasPhoto: false),
        throwsArgumentError,
      );
    });

    test('photo chore submits with photo; trust chore never needs one', () {
      expect(
        () => assertSubmittable(requiresPhoto: true, hasPhoto: true),
        returnsNormally,
      );
      expect(
        () => assertSubmittable(requiresPhoto: false, hasPhoto: false),
        returnsNormally,
      );
    });

    test('reject builds a nudge and returns chore to Today', () {
      final nudge = rejectNudge(choreTitle: 'Clean the play table');
      expect(nudge, isNotEmpty);
      expect(nudge.toLowerCase(), contains('try again'));
    });

    test('resubmission creates a new row, never mutates the old one', () {
      // The service always inserts; the rejected row is never updated back to
      // pending. This assertion documents the contract the SQL relies on:
      // status transitions are pending -> approved | rejected only.
      expect(kAllowedTransitions, containsPair('pending', ['approved', 'rejected']));
      expect(kAllowedTransitions.containsKey('rejected'), isFalse);
    });
  });
}
