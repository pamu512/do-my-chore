import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/kid/mark_done_screen.dart';
import 'package:do_my_chore/services/queries.dart';

KidChoreCard _bed({String? nudge}) => KidChoreCard(
      id: 'c1',
      title: 'Make your bed',
      cadence: 'daily',
      weightPct: 40,
      requiresPhoto: false,
      isMakeup: false,
      isBonus: false,
      nudge: nudge,
    );

void main() {
  testWidgets('retry uses A note from your parent', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MarkDoneView(
        chore: _bed(nudge: 'Whole bed, bright light.'),
        weeksN: 14,
        sent: false,
        submitting: false,
        onSubmit: () {},
        onBack: () {},
      ),
    ));
    expect(find.text('A note from your parent'), findsOneWidget);
    expect(find.text('PARENT SAID'), findsNothing);
    expect(find.text('Whole bed, bright light.'), findsOneWidget);
    expect(find.text('Done! Send to parent'), findsOneWidget);
  });

  testWidgets('after send stays on confirmation, does not pop', (tester) async {
    var popped = false;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onPopPage: (route, result) {
          popped = true;
          return route.didPop(result);
        },
        pages: [
          MaterialPage(
            child: MarkDoneView(
              chore: _bed(),
              weeksN: 14,
              sent: true,
              submitting: false,
              onSubmit: () {},
              onBack: () {},
            ),
          ),
        ],
      ),
    ));
    expect(find.text('Sent to your parent.'), findsOneWidget);
    expect(
      find.text('The bar moves the moment they take a look.'),
      findsOneWidget,
    );
    expect(find.text('Back to today'), findsOneWidget);
    expect(popped, isFalse);
  });
}
