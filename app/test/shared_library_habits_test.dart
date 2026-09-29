import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ai_service.dart';
import 'package:do_my_chore/services/chore_library.dart';
import 'package:do_my_chore/services/chore_progress_math.dart';
import 'package:do_my_chore/services/encouragement.dart';
import 'package:do_my_chore/services/goal_service.dart';
import 'package:do_my_chore/services/queries.dart';

KidChoreCard _card({
  required String id,
  required String title,
  required double weight,
  String cadence = 'daily',
  String? libraryChoreId,
  String? status,
  DateTime? at,
  String? nudge,
  bool requiresPhoto = true,
}) {
  return KidChoreCard(
    id: id,
    title: title,
    cadence: cadence,
    weightPct: weight,
    requiresPhoto: requiresPhoto,
    isMakeup: false,
    isBonus: false,
    nudge: nudge,
    latestStatus: status,
    latestCreatedAt: at,
    libraryChoreId: libraryChoreId,
  );
}

void main() {
  group('chore library catalog ids', () {
    test('deterministic plan stamps stable ids; same habit same id every time',
        () {
      final a = buildDeterministicPlan(
        title: 'Disneyland',
        targetAmount: 3500,
        weeks: 14,
        kidAge: 9,
      );
      final b = buildDeterministicPlan(
        title: 'Ice cream',
        targetAmount: 8,
        weeks: 4,
        kidAge: 9,
      );
      expect(a.chores.map((c) => c.libraryChoreId).toList(), [
        'make-your-bed',
        'wash-the-dishes',
        'fold-the-laundry',
        'plan-the-park-itinerary',
      ]);
      expect(
        b.chores.map((c) => c.libraryChoreId).toList(),
        a.chores.map((c) => c.libraryChoreId).toList(),
      );
      expect(libraryHabitById('make-your-bed')?.title, 'Make your bed');
    });

    test('little-kid catalog uses its own ids, not the 8+ bed id', () {
      final plan = buildDeterministicPlan(
        title: 'Zoo',
        targetAmount: 40,
        weeks: 6,
        kidAge: 6,
      );
      expect(plan.chores.map((c) => c.libraryChoreId).toList(), [
        'tidy-your-room',
        'set-and-clear-the-table',
        'fold-the-laundry',
        'plan-the-week-together',
      ]);
      expect(plan.chores.any((c) => c.libraryChoreId == 'make-your-bed'),
          isFalse);
    });

    test('fold-the-laundry is the same catalog id in both age bands', () {
      expect(
        libraryForAge(6).any((h) => h.id == 'fold-the-laundry'),
        isTrue,
      );
      expect(
        libraryForAge(9).any((h) => h.id == 'fold-the-laundry'),
        isTrue,
      );
    });

    test('validatePlan rejects an initial-plan chore with no library id', () {
      final bad = AiPlanSuggestion(
        weeklyParentSave: 250,
        why: 'why',
        chores: const [
          ChoreSpec(
              title: 'Make your bed',
              cadence: 'daily',
              weightPct: 40,
              requiresPhoto: true),
          ChoreSpec(
              title: 'Wash the dishes',
              cadence: 'daily',
              weightPct: 30,
              requiresPhoto: true),
          ChoreSpec(
              title: 'Fold the laundry',
              cadence: 'weekly',
              weightPct: 20,
              requiresPhoto: true),
          ChoreSpec(
              title: 'Plan the park itinerary',
              cadence: 'once',
              weightPct: 10,
              requiresPhoto: false),
        ],
      );
      expect(validatePlan(bad), contains('library'));
    });
  });

  group('collapseTodayByLibraryId', () {
    final now = DateTime(2026, 9, 29, 10);

    test('same library id across two active goals collapses to one row', () {
      final rows = collapseTodayByLibraryId([
        _card(
            id: 'disney-bed',
            title: 'Make your bed',
            weight: 40,
            libraryChoreId: 'make-your-bed'),
        _card(
            id: 'ice-bed',
            title: 'Make your bed',
            weight: 100,
            cadence: 'once',
            libraryChoreId: 'make-your-bed'),
        _card(
            id: 'disney-dishes',
            title: 'Wash the dishes',
            weight: 30,
            libraryChoreId: 'wash-the-dishes'),
      ], now: now);
      expect(rows.length, 2);
      expect(rows.map((c) => c.libraryChoreId).toList(),
          ['make-your-bed', 'wash-the-dishes']);
      final bed = rows.first;
      expect(bed.title, 'Make your bed');
      expect(submissionChoreIds(bed), ['disney-bed', 'ice-bed']);
      expect(bed.sharedGoalCount, 2);
    });

    test('custom chores with the same title never merge', () {
      final rows = collapseTodayByLibraryId([
        _card(id: 'a', title: 'Make your bed', weight: 40),
        _card(id: 'b', title: 'Make your bed', weight: 100, cadence: 'once'),
      ], now: now);
      expect(rows.length, 2);
      expect(submissionChoreIds(rows[0]), ['a']);
      expect(submissionChoreIds(rows[1]), ['b']);
    });

    test('different library ids stay two rows even with similar titles', () {
      final rows = collapseTodayByLibraryId([
        _card(
            id: 'a',
            title: 'Tidy your room',
            weight: 40,
            libraryChoreId: 'tidy-your-room'),
        _card(
            id: 'b',
            title: 'Tidy your room',
            weight: 40,
            libraryChoreId: 'make-your-bed'),
      ], now: now);
      expect(rows.length, 2);
    });

    test('cluster row is open if any member is still open', () {
      final rows = collapseTodayByLibraryId([
        _card(
          id: 'disney-bed',
          title: 'Make your bed',
          weight: 40,
          libraryChoreId: 'make-your-bed',
          status: 'pending',
          at: now,
        ),
        _card(
          id: 'ice-bed',
          title: 'Make your bed',
          weight: 100,
          cadence: 'once',
          libraryChoreId: 'make-your-bed',
        ),
      ], now: now);
      expect(rows.single.rowKind(now), KidRowKind.open);
    });
  });

  group('multi-goal credit', () {
    test('one cluster approval credits each goal with its own weight math', () {
      final credits = clusterCreditPreviews([
        (
          weightPct: 40,
          cadence: 'daily',
          weeksN: 14,
        ),
        (
          weightPct: 100,
          cadence: 'once',
          weeksN: 4,
        ),
      ]);
      expect(credits[0], closeTo(40 / (7 * 14), 1e-9));
      expect(credits[1], 100);
      expect(credits[0] == credits[1], isFalse);
    });

    test('kid progress after one shared approval is per-goal, not shared', () {
      final disney = kidProgressPct(
        chores: [
          (weightPct: 40, cadence: 'daily', approvedCount: 1),
        ],
        weeksN: 14,
      );
      final ice = kidProgressPct(
        chores: [
          (weightPct: 100, cadence: 'once', approvedCount: 1),
        ],
        weeksN: 4,
      );
      expect(disney, closeTo(40 / 98, 1e-9));
      expect(ice, 100);
    });
  });

  group('pending cluster', () {
    test('pending cards with the same library id collapse to one inbox card',
        () {
      final cards = collapsePendingByLibraryId(const [
        PendingApproval(
          submissionId: 's1',
          choreTitle: 'Make your bed',
          cadence: 'daily',
          weightPct: 40,
          requiresPhoto: true,
          libraryChoreId: 'make-your-bed',
        ),
        PendingApproval(
          submissionId: 's2',
          choreTitle: 'Make your bed',
          cadence: 'once',
          weightPct: 100,
          requiresPhoto: true,
          libraryChoreId: 'make-your-bed',
        ),
        PendingApproval(
          submissionId: 's3',
          choreTitle: 'Wash the dishes',
          cadence: 'daily',
          weightPct: 30,
          requiresPhoto: true,
          libraryChoreId: 'wash-the-dishes',
        ),
      ]);
      expect(cards.length, 2);
      expect(clusterSubmissionIds(cards.first), ['s1', 's2']);
      expect(cards.first.sharedGoalCount, 2);
    });

    test('custom pending cards never fan out', () {
      final cards = collapsePendingByLibraryId(const [
        PendingApproval(
          submissionId: 's1',
          choreTitle: 'Make your bed',
          cadence: 'daily',
          weightPct: 40,
          requiresPhoto: true,
        ),
        PendingApproval(
          submissionId: 's2',
          choreTitle: 'Make your bed',
          cadence: 'once',
          weightPct: 100,
          requiresPhoto: true,
        ),
      ]);
      expect(cards.length, 2);
      expect(clusterSubmissionIds(cards[0]), ['s1']);
    });
  });
}
