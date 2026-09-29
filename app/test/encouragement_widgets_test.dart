import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/features/kid/encouragement_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('next-try note uses parent eyebrow, not PARENT SAID',
      (tester) async {
    await tester.pumpWidget(
        _wrap(const KidNextTryNote(note: 'Whole bed, bright light.')));
    expect(find.text('A note from your parent'), findsOneWidget);
    expect(find.text('PARENT SAID'), findsNothing);
    expect(find.text('Whole bed, bright light.'), findsOneWidget);
    expect(find.textContaining('Try again'), findsNothing);
  });

  testWidgets('badge says NEXT TRY', (tester) async {
    await tester.pumpWidget(_wrap(const KidNextTryBadge()));
    expect(find.text('NEXT TRY'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
  });

  testWidgets('day-done card names the percent chip and keeps copy calm',
      (tester) async {
    await tester.pumpWidget(_wrap(const KidDayDoneCard(movedPct: 0.714)));
    expect(find.text("That's today done."), findsOneWidget);
    expect(find.textContaining('moved the bar today'), findsOneWidget);
    expect(find.textContaining('+0.7%'), findsOneWidget);
  });

  testWidgets('day-done skips confetti when animations are disabled',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _wrap(const KidDayDoneCard(movedPct: 1.2)),
    ));
    await tester.pump();
    expect(find.byKey(const Key('dmc-confetti')), findsNothing);
  });

  testWidgets('pace card is path copy only', (tester) async {
    await tester.pumpWidget(_wrap(const KidPaceCard(
      title: paceTitle,
      body: paceBody,
    )));
    expect(find.text(paceTitle), findsOneWidget);
    expect(find.text(paceBody), findsOneWidget);
    expect(find.textContaining('Slow week'), findsNothing);
    expect(find.textContaining('catch-up'), findsNothing);
  });

  testWidgets('sent confirmation copy', (tester) async {
    await tester.pumpWidget(_wrap(KidSentConfirmation(onBack: () {})));
    expect(find.text('Sent to your parent.'), findsOneWidget);
    expect(
      find.text('The bar moves the moment they take a look.'),
      findsOneWidget,
    );
    expect(find.text('Back to today'), findsOneWidget);
  });

  testWidgets('finale has no dollars', (tester) async {
    await tester.pumpWidget(_wrap(const KidGoalEarnedFinale(
      goalTitle: 'Disneyland',
      handOff:
          'Your parent takes it from here - talk about the trip together tonight.',
    )));
    expect(find.text('You earned it.'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('Disneyland'), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });
}

const paceTitle = 'Two check-ins today puts the week back on pace.';
const paceBody = 'Bed and dishes are right there - each one moves the bar.';
