import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/kid/today_screen.dart';
import 'package:do_my_chore/services/queries.dart';

KidChoreCard _card({
  required String id,
  required String title,
  required double weight,
  String cadence = 'daily',
  String? status,
  DateTime? at,
  String? nudge,
}) {
  return KidChoreCard(
    id: id,
    title: title,
    cadence: cadence,
    weightPct: weight,
    requiresPhoto: true,
    isMakeup: false,
    isBonus: false,
    nudge: nudge,
    latestStatus: status,
    latestCreatedAt: at,
  );
}

GoalProgressView _goal({
  double pct = 23,
  int weeksElapsed = 0,
  int weeksN = 14,
}) {
  return GoalProgressView(
    id: 'g1',
    title: 'Disneyland',
    targetAmount: 3500,
    goalMode: 'family_trip',
    allowMakeup: false,
    targetDate: DateTime(2026, 9, 28).add(Duration(days: 7 * weeksN)),
    weeksN: weeksN,
    weeksElapsed: weeksElapsed,
    choreProgressPct: pct,
    parentSaved: 0,
    planWeightSum: 100,
    weeklyParentSave: 250,
  );
}

void main() {
  final now = DateTime(2026, 9, 28, 10);

  testWidgets('Today shows next try, hides try-again, keeps sent rows',
      (tester) async {
    final chores = [
      _card(
        id: 'c1',
        title: 'Make your bed',
        weight: 40,
        status: 'pending',
        at: now,
      ),
      _card(
        id: 'c2',
        title: 'Wash the dishes',
        weight: 30,
        nudge: 'Whole sink, bright light.',
        status: 'rejected',
        at: now,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: chores,
          goals: [_goal()],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text('NEXT TRY'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
    expect(find.textContaining('Try again'), findsNothing);
    expect(find.text('Whole sink, bright light.'), findsOneWidget);
    expect(find.text('Sent - waiting for your parent'), findsOneWidget);
    expect(find.text('Every check-in moves the bar.'), findsOneWidget);
    expect(find.textContaining('100% earns'), findsNothing);
  });

  testWidgets('slow week shows path-only pace card from real math',
      (tester) async {
    final chores = [
      _card(id: 'c1', title: 'Make your bed', weight: 40),
      _card(id: 'c2', title: 'Wash the dishes', weight: 30),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: chores,
          goals: [_goal(pct: 20, weeksElapsed: 7)],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(
      find.text('Two check-ins today puts the week back on pace.'),
      findsOneWidget,
    );
    expect(
      find.text('Bed and dishes are right there - each one moves the bar.'),
      findsOneWidget,
    );
    expect(find.text('Every check-in moves it. The trip stays put.'),
        findsOneWidget);
    expect(find.textContaining('Slow week'), findsNothing);
    expect(find.textContaining('catch-up pile'), findsNothing);
  });

  testWidgets('all sent shows day-done and keeps pending rows', (tester) async {
    final chores = [
      _card(
          id: 'c1',
          title: 'Make your bed',
          weight: 40,
          status: 'pending',
          at: now),
      _card(
          id: 'c2',
          title: 'Wash the dishes',
          weight: 30,
          status: 'pending',
          at: now),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: chores,
          goals: [_goal(pct: 23)],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text("That's today done."), findsOneWidget);
    expect(find.text('Sent - waiting for your parent'), findsNWidgets(2));
    expect(find.textContaining('moved the bar today'), findsOneWidget);
    expect(
      find.text('Two check-ins today puts the week back on pace.'),
      findsNothing,
    );
  });

  testWidgets('100 percent shows finale without dollars or chore list',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KidTodayBody(
          chores: [
            _card(id: 'c1', title: 'Make your bed', weight: 40),
          ],
          goals: [_goal(pct: 100)],
          now: now,
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.text('You earned it.'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('talk about the trip together'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.text("TODAY'S CHORES"), findsNothing);
  });
}
