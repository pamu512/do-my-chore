import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:do_my_chore/core/demo_auth.dart';
import 'package:do_my_chore/features/parent/new_goal_screen.dart';
import 'package:do_my_chore/services/edge_ai_client.dart';
import 'package:do_my_chore/services/goal_service.dart';

/// UI contract: parent types free-text goal only (amount blank) → Suggest
/// shows estimate bands + weekly save + chore plan.
///
/// Green under plain `flutter test` (CI): without DEMO_WALK the client first
/// tries the suggest-plan function, which times out in the test binding after
/// 8s of virtual time and falls back to the local deterministic result - so
/// the pump budget below must exceed that timeout.
void main() {
  test('localGoalFirstSuggest with null amount yields family_trip prior', () {
    final r = localGoalFirstSuggest(
      title: 'Miami with the family for Christmas',
      weeks: 14,
      kidAge: 8,
      goalMode: 'family_trip',
    );
    expect(r.estimate.likely, 1200);
    expect(r.estimate.provider, 'deterministic');
    expect(r.plan.chores.length, greaterThanOrEqualTo(4));
    expect(r.plan.weeklyParentSave, greaterThan(0));
    expect(r.source, 'deterministic');
  });

  testWidgets('plain-text-only goal Suggest shows bands and plan', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const authOptions = AuthClientOptions(autoRefreshToken: false);
    final parent = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: authOptions,
    );
    final kid = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: authOptions,
    );
    // Cancel GoTrue periodic timers before the test binding checks invariants.
    parent.auth.stopAutoRefresh();
    kid.auth.stopAutoRefresh();

    final service = GoalService(RoleClients(parent: parent, kid: kid));

    await tester.pumpWidget(
      MaterialApp(home: NewGoalScreen(goalService: service)),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(
      fields.at(0),
      'Miami with the family for Christmas',
    );
    await tester.pump();

    expect(tester.widget<TextField>(fields.at(1)).controller?.text ?? '', isEmpty);

    await tester.tap(find.text('Suggest plan'));
    // Without DEMO_WALK the function invoke times out at 8s virtual time
    // before the local fallback renders; 200 x 50ms covers it with margin.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('SAVE ESTIMATE').evaluate().isNotEmpty ||
          find.textContaining('Could not build plan').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Could not build plan'), findsNothing,
        reason: 'Suggest must not error when amount is blank');
    expect(find.text('SAVE ESTIMATE'), findsOneWidget);
    expect(find.text('Offline estimate'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Likely'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('\$800'), findsOneWidget);
    expect(find.text('\$1200'), findsWidgets);
    expect(find.text('\$1800'), findsOneWidget);
    expect(
      tester.widget<TextField>(fields.at(1)).controller?.text,
      '1200',
    );

    final listScrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    if (listScrollable.evaluate().isNotEmpty &&
        find.text('Accept plan').evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text('Accept plan'),
        300,
        scrollable: listScrollable.first,
        maxScrolls: 40,
      );
    }

    expect(find.text('WHY THIS PLAN'), findsOneWidget);
    expect(find.textContaining('Weekly top-up'), findsOneWidget);
    expect(find.textContaining('/wk'), findsWidgets);
    expect(find.text('THE PLAN'), findsOneWidget);
    expect(find.text('Accept plan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    parent.auth.stopAutoRefresh();
    kid.auth.stopAutoRefresh();
  });

  testWidgets('target date is not an editable text field', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      final service = _goalService();
      final anchor = DateTime.now().add(const Duration(days: 98));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          home: NewGoalScreen(goalService: service),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Target date',
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('target-date-field')),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );
      expect(find.byType(TextField), findsNWidgets(2));

      final shown = _mediumDate(tester, anchor);
      expect(find.text(shown), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('target-date-field'))),
        isSemantics(
          label: 'Target date',
          value: shown,
          isButton: true,
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      handle.dispose();
    }
  });

  testWidgets('picking a target date feeds suggest plan', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _goalService();
    final anchor = DateTime.now().add(const Duration(days: 98));
    final day = anchor.day == 15 ? 14 : 15;
    final expected = DateTime.utc(anchor.year, anchor.month, day);
    DateTime? seen;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        home: NewGoalScreen(
          goalService: service,
          suggestPlan: ({
            required String title,
            double? targetAmount,
            required DateTime targetDate,
            required int kidAge,
            required String goalMode,
          }) async {
            seen = targetDate;
            return localGoalFirstSuggest(
              title: title,
              targetAmount: targetAmount,
              weeks: 14,
              kidAge: kidAge,
              goalMode: goalMode,
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('target-date-field')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    final cell = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('$day'),
    );
    expect(cell, findsWidgets);
    await tester.tap(cell.last);
    await tester.pumpAndSettle();
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).okButtonLabel;
    await tester.tap(find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text(ok),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    final shown = _mediumDate(tester, expected);
    expect(find.text(shown), findsOneWidget);

    await tester.tap(find.text('Suggest plan'));
    await tester.pump();
    await tester.pump();

    expect(seen, expected);
    expect(find.textContaining('Could not build plan'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

GoalService _goalService() {
  const authOptions = AuthClientOptions(autoRefreshToken: false);
  final parent = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
    authOptions: authOptions,
  );
  final kid = SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
    authOptions: authOptions,
  );
  parent.auth.stopAutoRefresh();
  kid.auth.stopAutoRefresh();
  addTearDown(() {
    parent.auth.stopAutoRefresh();
    kid.auth.stopAutoRefresh();
  });
  return GoalService(RoleClients(parent: parent, kid: kid));
}

String _mediumDate(WidgetTester tester, DateTime utcDay) {
  return MaterialLocalizations.of(tester.element(find.byType(NewGoalScreen)))
      .formatMediumDate(DateTime(utcDay.year, utcDay.month, utcDay.day));
}
