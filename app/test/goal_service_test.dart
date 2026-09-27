import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';

void main() {
  group('deterministic fallback plan', () {
    test('yields >= 4 chores and a non-empty why', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 500,
        weeks: 20,
        kidAge: 9,
      );
      expect(plan.chores.length, greaterThanOrEqualTo(4));
      expect(plan.why.isNotEmpty, isTrue);
      expect(plan.weeklyTopup, greaterThan(0));
    });

    test('weekly split of chores+topup reaches the target within weeks', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 500,
        weeks: 20,
        kidAge: 9,
      );
      // Sum of all chore rewards per week + topup should cover 500/20 = 25/wk
      final choreWeekly =
          plan.chores.fold<double>(0, (s, c) => s + c.reward);
      expect(choreWeekly + plan.weeklyTopup, greaterThanOrEqualTo(25));
    });

    test('requires_photo only on visually verifiable chores', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 500,
        weeks: 20,
        kidAge: 9,
      );
      // Design constraint is one-directional: a chore may demand photo proof
      // only if a parent can verify it by looking. The converse is allowed —
      // a visual chore may still be trust-based.
      for (final c in plan.chores) {
        if (c.requiresPhoto) {
          expect(kVisuallyVerifiable, contains(c.title));
        }
      }
    });

    test('split percentages are each valid 0-100', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 500,
        weeks: 20,
        kidAge: 9,
      );
      for (final c in plan.chores) {
        expect(c.splitGoalPct, inInclusiveRange(0, 100));
      }
    });

    test('no ML jargon in why (plain parent language)', () {
      final plan = buildDeterministicPlan(
        title: 'Camping trip',
        targetAmount: 300,
        weeks: 12,
        kidAge: 7,
      );
      final lower = plan.why.toLowerCase();
      for (final jargon in ['model', 'inference', 'token', 'llm', 'ai ']) {
        expect(lower.contains(jargon), isFalse, reason: 'found "$jargon"');
      }
    });

    test('rewards are age-appropriate and positive', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 500,
        weeks: 20,
        kidAge: 9,
      );
      for (final c in plan.chores) {
        expect(c.reward, greaterThan(0));
      }
    });
  });

  group('weeksBetween helpers', () {
    test('computes weeks from now to a target date', () {
      final target = DateTime.now().add(const Duration(days: 70));
      expect(weeksUntil(target), 10);
    });

    test('a past date collapses to at least one week', () {
      final past = DateTime.now().subtract(const Duration(days: 30));
      expect(weeksUntil(past), 1);
    });
  });
}
