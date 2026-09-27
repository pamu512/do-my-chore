import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/shell/role_switch_shell.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RoleSwitchShell()),
    );
  }

  testWidgets('defaults to Parent Home', (tester) async {
    await pumpShell(tester);
    expect(find.text('Parent Home'), findsOneWidget);
    expect(find.text('Kid Today'), findsNothing);
  });

  testWidgets('toggling to Kid shows Kid Today', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Kid'));
    await tester.pumpAndSettle();
    expect(find.text('Kid Today'), findsOneWidget);
    expect(find.text('Parent Home'), findsNothing);
  });

  testWidgets('toggling back to Parent restores Parent Home', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Kid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parent'));
    await tester.pumpAndSettle();
    expect(find.text('Parent Home'), findsOneWidget);
  });
}
