import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';
import 'package:do_my_chore/services/goal_service.dart';

/// Pins the accept-time validation (rev 3): weights must cover 100%, cadences
/// must be valid, makeup never ships inside the initial plan, and a non-visual
/// chore must never land in the DB with requires_photo: true.
void main() {
  AiPlanSuggestion goodPlan() => AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'It covers the cost and the habits fit the school week.',
        chores: const [
          ChoreSpec(
              title: 'Make your bed',
              cadence: 'daily',
              weightPct: 40,
              requiresPhoto: true,
              libraryChoreId: 'make-your-bed'),
          ChoreSpec(
              title: 'Wash the dishes',
              cadence: 'daily',
              weightPct: 30,
              requiresPhoto: true,
              libraryChoreId: 'wash-the-dishes'),
          ChoreSpec(
              title: 'Fold the laundry',
              cadence: 'weekly',
              weightPct: 20,
              requiresPhoto: true,
              libraryChoreId: 'fold-the-laundry'),
          ChoreSpec(
              title: 'Plan the park itinerary',
              cadence: 'once',
              weightPct: 10,
              requiresPhoto: false,
              libraryChoreId: 'plan-the-park-itinerary'),
        ],
      );

  group('validatePlan (accept-time guard, rev 3)', () {
    test('a good 100% plan passes', () {
      expect(validatePlan(goodPlan()), isNull);
    });

    test('weights summing under 100 is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 30, requiresPhoto: true, libraryChoreId: 'make-your-bed'),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 20, requiresPhoto: true, libraryChoreId: 'wash-the-dishes'),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 15, requiresPhoto: true, libraryChoreId: 'fold-the-laundry'),
          ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 10, requiresPhoto: false, libraryChoreId: 'plan-the-park-itinerary'),
        ],
      );
      final problem = validatePlan(bad);
      expect(problem, isNotNull);
      expect(problem, contains('100%'));
    });

    test('weights summing over 100 (oversubscribe) is allowed', () {
      final over = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 50, requiresPhoto: true, libraryChoreId: 'make-your-bed'),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 40, requiresPhoto: true, libraryChoreId: 'wash-the-dishes'),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 30, requiresPhoto: true, libraryChoreId: 'fold-the-laundry'),
          ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 20, requiresPhoto: false, libraryChoreId: 'plan-the-park-itinerary'),
        ],
      );
      expect(validatePlan(over), isNull);
    });

    test('invalid cadence is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'hourly', weightPct: 40, requiresPhoto: true),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 30, requiresPhoto: true),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true),
          ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 10, requiresPhoto: false),
        ],
      );
      expect(validatePlan(bad), contains('cadence'));
    });

    test('makeup chore inside the initial plan is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 40, requiresPhoto: true, libraryChoreId: 'make-your-bed'),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 30, requiresPhoto: true, libraryChoreId: 'wash-the-dishes'),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true, libraryChoreId: 'fold-the-laundry'),
          ChoreSpec(
              title: 'Emergency catch-up sweep',
              cadence: 'once',
              weightPct: 10,
              requiresPhoto: false,
              isMakeup: true),
        ],
      );
      expect(validatePlan(bad), contains('Makeup'));
    });

    test('trust chore with requires_photo is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Read a chapter', cadence: 'daily', weightPct: 40, requiresPhoto: true),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 30, requiresPhoto: true),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true),
          ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 10, requiresPhoto: false),
        ],
      );
      final problem = validatePlan(bad);
      expect(problem, isNotNull);
      expect(problem, contains('Read a chapter'));
    });

    test('fewer than 4 chores is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 100, requiresPhoto: true),
        ],
      );
      expect(validatePlan(bad), contains('4-8'));
    });

    test('empty why is rejected (parent deserves the explanation)', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: '  ',
        chores: goodPlan().chores,
      );
      expect(validatePlan(bad), isNotNull);
    });

    test('zero or negative weight is rejected', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 0, requiresPhoto: true),
          ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 30, requiresPhoto: true),
          ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true),
          ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 10, requiresPhoto: false),
        ],
      );
      expect(validatePlan(bad), isNotNull);
    });
  });
}
