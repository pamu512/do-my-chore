import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';
import 'package:do_my_chore/services/goal_service.dart';

/// Pins the accept-time validation: a non-visual chore must never land in the
/// DB with requires_photo: true, regardless of what a suggestion claims.
void main() {
  AiPlanSuggestion goodPlan() => AiPlanSuggestion(
        weeklyTopup: 25,
        why: 'Because it adds up nicely over the term.',
        chores: const [
          ChoreSpec(
              title: 'Read for 20 minutes',
              reward: 3,
              requiresPhoto: false,
              splitGoalPct: 100),
          ChoreSpec(
              title: 'Make your bed', reward: 2, requiresPhoto: false, splitGoalPct: 100),
          ChoreSpec(
              title: 'Clean the play table',
              reward: 5,
              requiresPhoto: true,
              splitGoalPct: 80),
          ChoreSpec(
              title: 'Fold the laundry',
              reward: 4,
              requiresPhoto: false,
              splitGoalPct: 60),
        ],
      );

  group('validatePlan (accept-time guard)', () {
    test('a good plan passes', () {
      expect(validatePlan(goodPlan()), isNull);
    });

    test('trust chore with requires_photo is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyTopup: 25,
        why: 'why',
        chores: const [
          ChoreSpec(
              title: 'Read a chapter', reward: 3, requiresPhoto: true, splitGoalPct: 100),
          ChoreSpec(title: 'Make your bed', reward: 2, requiresPhoto: false, splitGoalPct: 100),
          ChoreSpec(
              title: 'Clean the play table', reward: 5, requiresPhoto: true, splitGoalPct: 80),
          ChoreSpec(title: 'Fold the laundry', reward: 4, requiresPhoto: false, splitGoalPct: 60),
        ],
      );
      final problem = validatePlan(bad);
      expect(problem, isNotNull);
      expect(problem, contains('Read a chapter'));
    });

    test('fewer than 4 chores is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyTopup: 25,
        why: 'why',
        chores: const [
          ChoreSpec(
              title: 'Clean the play table', reward: 5, requiresPhoto: true, splitGoalPct: 80),
        ],
      );
      expect(validatePlan(bad), contains('4-8'));
    });

    test('empty why is rejected (parent deserves the explanation)', () {
      final bad = AiPlanSuggestion(
        weeklyTopup: 25,
        why: '  ',
        chores: const [
          ChoreSpec(
              title: 'Clean the play table', reward: 5, requiresPhoto: true, splitGoalPct: 80),
          ChoreSpec(title: 'Read for 20 minutes', reward: 3, requiresPhoto: false, splitGoalPct: 100),
          ChoreSpec(title: 'Make your bed', reward: 2, requiresPhoto: false, splitGoalPct: 100),
          ChoreSpec(title: 'Fold the laundry', reward: 4, requiresPhoto: false, splitGoalPct: 60),
        ],
      );
      expect(validatePlan(bad), isNotNull);
    });
  });
}
