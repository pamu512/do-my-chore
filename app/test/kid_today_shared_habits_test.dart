import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/kid/today_screen.dart';
import 'package:do_my_chore/services/queries.dart';

KidChoreCard _card({
  required String id,
  required String title,
  required double weight,
  String cadence = 'daily',
  String? libraryChoreId,
}) {
  return KidChoreCard(
    id: id,
    title: title,
    cadence: cadence,
    weightPct: weight,
    requiresPhoto: true,
    isMakeup: false,
    isBonus: false,
    libraryChoreId: libraryChoreId,
  );
}

GoalProgressView _goal({
  String id = 'g1',
  String title = 'Disneyland',
  double pct = 23,
}) {
  return GoalProgressView(
    id: id,
    title: title,
    targetAmount: 3500,
    goalMode: 'family_trip',
    allowMakeup: false,
    targetDate: DateTime(2026, 12, 31),
    weeksN: 14,
    weeksElapsed: 0,
    choreProgressPct: pct,
    parentSaved: 0,
    planWeightSum: 100,
    weeklyParentSave: 250,
  );
}

void main() {
  final now = DateTime(2026, 9, 29, 10);

  testWidgets('shared library habit is one Today row across two goals',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: [
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
          ],
          goals: [
            _goal(),
            _goal(id: 'g2', title: 'Ice cream', pct: 0),
          ],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text('Make your bed'), findsOneWidget);
    expect(find.textContaining('counts for 2 goals'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('custom chores with the same title stay two Today rows',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: [
            _card(id: 'a', title: 'Make your bed', weight: 40),
            _card(id: 'b', title: 'Make your bed', weight: 100, cadence: 'once'),
          ],
          goals: [_goal()],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text('Make your bed'), findsNWidgets(2));
    expect(find.textContaining('counts for 2 goals'), findsNothing);
  });
}
