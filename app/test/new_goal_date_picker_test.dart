import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:do_my_chore/core/demo_auth.dart';
import 'package:do_my_chore/features/parent/new_goal_screen.dart';
import 'package:do_my_chore/services/goal_service.dart';

/// Basics New Goal: target date is native showDatePicker, not free-typed yyyy-MM-dd.
void main() {
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
      // Goal name, total cost, kid age.
      expect(find.byType(TextField), findsNWidgets(3));

      final shown = _mediumDate(tester, anchor);
      expect(find.text(shown), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('target-date-field'))),
        matchesSemantics(
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

  testWidgets('picking a target date updates the field and suggest still works',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _goalService();
    final anchor = DateTime.now().add(const Duration(days: 98));
    final day = anchor.day == 15 ? 14 : 15;
    final expected = DateTime.utc(anchor.year, anchor.month, day);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        home: NewGoalScreen(goalService: service),
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

    await tester.enterText(find.byType(TextField).first, 'Disneyland');
    await tester.pump();
    await tester.tap(find.text('Suggest plan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Could not build plan'), findsNothing);
    expect(find.text('Accept plan'), findsOneWidget);

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
