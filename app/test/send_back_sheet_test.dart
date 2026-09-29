import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/parent/send_back_sheet.dart';
import 'package:do_my_chore/services/chore_service.dart';

void main() {
  testWidgets('preview tracks the textarea and matches kid eyebrow',
      (tester) async {
    String? confirmed;
    final initial = rejectNudge(choreTitle: 'Make your bed');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendBackSheet(
          kidName: 'Arjun',
          choreTitle: 'Make your bed',
          initialNote: initial,
          onCancel: () {},
          onConfirm: (n) => confirmed = n,
        ),
      ),
    ));
    expect(find.text('Send back with a note'), findsOneWidget);
    expect(find.text('A note from your parent'), findsOneWidget);
    expect(find.text(initial), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Whole sheet in the frame.');
    await tester.pump();
    expect(find.text('Whole sheet in the frame.'), findsWidgets);
    await tester.tap(find.text('Send note'));
    expect(confirmed, 'Whole sheet in the frame.');
  });

  testWidgets('blank note confirms as the kind default', (tester) async {
    String? confirmed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SendBackSheet(
          kidName: 'Arjun',
          choreTitle: 'Make your bed',
          initialNote: rejectNudge(choreTitle: 'Make your bed'),
          onCancel: () {},
          onConfirm: (n) => confirmed = n,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Send note'));
    expect(confirmed, rejectNudge(choreTitle: 'Make your bed'));
  });
}
