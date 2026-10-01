import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';
import 'package:do_my_chore/services/goal_service.dart';

void main() {
  test('walkthrough inputs produce a valid plan', () {
    final plan = buildDeterministicPlan(
      title: 'Camping trip',
      targetAmount: 300,
      weeks: 14,
      kidAge: 8,
    );
    // ignore: avoid_print
    print('chores=${plan.chores.length} '
        'weightSum=${plan.chores.fold<double>(0, (s, c) => s + c.weightPct)} '
        'weeklySave=${plan.weeklyParentSave}');
    for (final c in plan.chores) {
      // ignore: avoid_print
      print('  ${c.title} | ${c.cadence} | ${c.weightPct} | photo=${c.requiresPhoto}');
    }
    expect(validatePlan(plan), isNull);
  });
}
