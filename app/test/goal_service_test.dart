import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';

void main() {
  group('deterministic fallback plan (rev 3)', () {
    test('yields >= 4 chores, a non-empty why, and a positive weekly save', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 8,
      );
      expect(plan.chores.length, greaterThanOrEqualTo(4));
      expect(plan.why.isNotEmpty, isTrue);
      expect(plan.weeklyParentSave, greaterThan(0));
    });

    test('Disneyland worked example: 3500 over 14 weeks saves 250 weekly', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 8,
      );
      expect(plan.weeklyParentSave, 250);
    });

    test('weights sum to at least 100 and each weight is positive', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 8,
      );
      expect(plan.weightSum, greaterThanOrEqualTo(100));
      for (final c in plan.chores) {
        expect(c.weightPct, greaterThan(0));
        expect(['once', 'daily', 'weekly'], contains(c.cadence));
      }
    });

    test('requires_photo only on visually verifiable chores', () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 8,
      );
      for (final c in plan.chores) {
        if (c.requiresPhoto) {
          expect(kVisuallyVerifiable, contains(c.title));
        }
      }
    });

    test('no makeup chores inside the initial plan (parent adds them later)',
        () {
      final plan = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 8,
      );
      for (final c in plan.chores) {
        expect(c.isMakeup, isFalse);
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
      for (final jargon in ['model', 'inference', 'token', 'llm', ' ai ']) {
        expect(lower.contains(jargon), isFalse, reason: 'found "$jargon"');
      }
    });
  });

  group('weeksUntil', () {
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
