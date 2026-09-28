import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/chore_progress_math.dart';
import 'package:do_my_chore/services/queries.dart';

GoalProgressView _view({
  double target = 3500,
  double saved = 0,
  double weeklyPlan = 250,
  int weeksN = 14,
  int weeksElapsed = 0,
  double chorePct = 0,
  double weightSum = 100,
  bool allowMakeup = false,
}) {
  return GoalProgressView(
    id: 'g1',
    title: 'Disneyland',
    targetAmount: target,
    goalMode: 'family_trip',
    allowMakeup: allowMakeup,
    targetDate: DateTime.now().add(Duration(days: 7 * weeksN)),
    weeksN: weeksN,
    weeksElapsed: weeksElapsed,
    choreProgressPct: chorePct,
    parentSaved: saved,
    planWeightSum: weightSum,
    weeklyParentSave: weeklyPlan,
  );
}

void main() {
  group('requiredWeeklySave', () {
    test('nothing saved: required equals plan rate', () {
      expect(
        requiredWeeklySave(target: 3500, saved: 0, weeksN: 14),
        closeTo(250, 0.001),
      );
    });

    test('parent kept up: required stays at plan rate', () {
      // 4 weeks in, 1000 saved, 10 left -> (3500-1000)/10 = 250
      expect(
        requiredWeeklySave(target: 3500, saved: 1000, weeksN: 10),
        closeTo(250, 0.001),
      );
    });

    test('parent skipped weeks: required climbs above plan rate', () {
      // 4 idle weeks -> 10 left, 0 saved -> 350
      expect(
        requiredWeeklySave(target: 3500, saved: 0, weeksN: 10),
        closeTo(350, 0.001),
      );
    });

    test('fully saved: nothing more required', () {
      expect(
        requiredWeeklySave(target: 3500, saved: 3500, weeksN: 3),
        equals(0),
      );
    });

    test('oversaved clamps at zero', () {
      expect(
        requiredWeeklySave(target: 3500, saved: 4000, weeksN: 3),
        equals(0),
      );
    });
  });

  group('GoalProgressView.parentBehind', () {
    test('on plan is not behind', () {
      final v = _view(saved: 0, weeksN: 14);
      expect(v.parentBehind, isFalse);
      expect(v.requiredWeeklyNow, closeTo(250, 0.001));
    });

    test('skipped weeks flip it behind with the catch-up rate', () {
      final v = _view(saved: 0, weeksN: 10);
      expect(v.parentBehind, isTrue);
      expect(v.requiredWeeklyNow, closeTo(350, 0.001));
    });

    test('tiny rounding slack does not count as behind', () {
      // saved such that required = 250.004 -> within tolerance
      final v = _view(saved: 3500 - 250.004 * 10, weeksN: 10);
      expect(v.parentBehind, isFalse);
    });
  });

  group('GoalProgressView.kidBehindPace (elapsed from created_at)', () {
    test('fresh goal: nothing elapsed, never behind', () {
      final v = _view(weeksElapsed: 0, chorePct: 0);
      expect(v.kidBehindPace, isFalse);
    });

    test('mid-goal below pace is behind', () {
      final v = _view(weeksElapsed: 6, weeksN: 14, chorePct: 10);
      expect(v.kidBehindPace, isTrue);
    });

    test('on the linear pace is not behind', () {
      // 6/14 elapsed -> pace 42.86; 60% progress is ahead
      final v = _view(weeksElapsed: 6, weeksN: 14, chorePct: 60);
      expect(v.kidBehindPace, isFalse);
    });

    test('deadline passed with shortfall is behind', () {
      final v = _view(weeksElapsed: 14, weeksN: 14, chorePct: 80);
      expect(v.kidBehindPace, isTrue);
    });
  });
}
