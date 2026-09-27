import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ledger_math.dart';

void main() {
  group('splitCredit', () {
    test('overshoot fills goal then pocket', () {
      final r = splitCredit(amount: 30, goalBalance: 90, targetAmount: 100);
      expect(r.goalCredit, 10);
      expect(r.pocketCredit, 20);
    });

    test('under target sends everything to goal', () {
      final r = splitCredit(amount: 15, goalBalance: 0, targetAmount: 100);
      expect(r.goalCredit, 15);
      expect(r.pocketCredit, 0);
    });

    test('exact fill leaves nothing for pocket', () {
      final r = splitCredit(amount: 10, goalBalance: 90, targetAmount: 100);
      expect(r.goalCredit, 10);
      expect(r.pocketCredit, 0);
    });

    test('goal already at target sends everything to pocket', () {
      final r = splitCredit(amount: 7, goalBalance: 100, targetAmount: 100);
      expect(r.goalCredit, 0);
      expect(r.pocketCredit, 7);
    });

    test('goal over target (defensive) sends everything to pocket', () {
      final r = splitCredit(amount: 5, goalBalance: 120, targetAmount: 100);
      expect(r.goalCredit, 0);
      expect(r.pocketCredit, 5);
    });

    test('fractional amounts split to the cent', () {
      final r = splitCredit(amount: 10.05, goalBalance: 99.98, targetAmount: 100);
      expect(r.goalCredit, 0.02);
      expect(r.pocketCredit, 10.03);
    });
  });

  group('sumLedger', () {
    test('sums goal bank (credits + topups) vs pocket', () {
      final entries = [
        LedgerEntry(kind: LedgerKind.goalCredit, amount: 10, goalId: 'g1'),
        LedgerEntry(kind: LedgerKind.parentTopup, amount: 25, goalId: 'g1'),
        LedgerEntry(kind: LedgerKind.goalCredit, amount: 4, goalId: 'g1'),
        LedgerEntry(kind: LedgerKind.pocketCredit, amount: 6, goalId: null),
      ];
      final s = sumLedger(entries);
      expect(s.goalBank, 39);
      expect(s.pocket, 6);
    });

    test('empty ledger sums to zero', () {
      final s = sumLedger(const []);
      expect(s.goalBank, 0);
      expect(s.pocket, 0);
    });
  });

  group('goalProgress', () {
    test('fraction under target', () {
      expect(goalProgress(goalBank: 50, targetAmount: 100), 0.5);
    });

    test('caps at 1.0 past target', () {
      expect(goalProgress(goalBank: 130, targetAmount: 100), 1.0);
    });

    test('zero target never divides by zero', () {
      expect(goalProgress(goalBank: 10, targetAmount: 0), 0.0);
    });
  });

  group('weeksToGoal', () {
    test('ceil division of remaining over weekly top-up', () {
      expect(weeksToGoal(goalBank: 90, targetAmount: 100, weeklyTopup: 25), 1);
      expect(weeksToGoal(goalBank: 0, targetAmount: 100, weeklyTopup: 25), 4);
      expect(weeksToGoal(goalBank: 10, targetAmount: 100, weeklyTopup: 30), 3);
    });

    test('already funded is zero weeks', () {
      expect(weeksToGoal(goalBank: 100, targetAmount: 100, weeklyTopup: 25), 0);
    });

    test('zero topup returns null (caller shows "top up now")', () {
      expect(weeksToGoal(goalBank: 0, targetAmount: 100, weeklyTopup: 0), isNull);
    });
  });
}
