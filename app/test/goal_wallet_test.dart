import 'dart:async';
import 'dart:io';

import 'package:do_my_chore/core/dmc_theme.dart';
import 'package:do_my_chore/features/kid/today_screen.dart';
import 'package:do_my_chore/features/parent/goal_wallet_screen.dart';
import 'package:do_my_chore/services/goal_wallet.dart';
import 'package:do_my_chore/services/queries.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'goal_wallet_harness.dart';

void main() {
  test('money display parses server amounts and rejects junk', () {
    expect(moneyToCents('10'), 1000);
    expect(moneyToCents('10.1'), 1010);
    expect(moneyToCents('10.10'), 1010);
    expect(canonicalMoney(4), '4.00');
    expect(canonicalMoney(4.5), '4.50');
    expect(canonicalMoney('2.01'), '2.01');
    expect(() => moneyToCents('-1'), throwsFormatException);
    expect(() => moneyToCents('10.999'), throwsFormatException);
    expect(formatFundingPercent(0.4), '40%');
    expect(formatFundingPercent(0.3), '30%');
    expect(formatFundingPercent(0), '0%');
    expect(normalizeAmountInput('\$1,000.50'), '1000.50');
    expect(withdrawAmountOrThrow('1'), '1.00');
    expect(withdrawAmountOrThrow('1.5'), '1.50');
    expect(
      () => withdrawAmountOrThrow('0'),
      throwsA(isA<GoalWalletException>()),
    );
    expect(
      () => withdrawAmountOrThrow('nope'),
      throwsA(isA<GoalWalletException>()),
    );
    expect(
      () => withdrawNoteOrThrow('n' * 501),
      throwsA(isA<GoalWalletException>()),
    );
    expect(effectiveCapturedCents(captured: '4.00', withdrawn: '1.00'), 300);
    expect(
      unfundedCents(goal: '10.00', captured: '4.00', withdrawn: '1.00'),
      700,
    );
    expect(effectiveCapturedCents(captured: '1.00', withdrawn: '4.00'), 0);
    expect(publicWalletError('That period is no longer waiting for approval.'),
        'That period is no longer waiting for approval.');
    expect(publicWalletError('client_secret=hidden'),
        'Could not update the goal wallet.');
    expect(publicWalletError('Bearer token'), 'Could not update the goal wallet.');
    expect(publicWalletError('eyJhbGciOi'), 'Could not update the goal wallet.');
    expect(publicWalletError(''), 'Could not update the goal wallet.');
    expect(publicWalletError('x' * 161), 'Could not update the goal wallet.');
    expect(canonicalMoney('10.000'), '10.00');
    expect(canonicalMoney('10.100'), '10.10');
    expect(canonicalMoney(2.33), '2.33');
    expect(() => moneyToCents('10.101'), throwsFormatException);
    expect(() => moneyToCents('10000000000'), throwsFormatException);
    expect(moneyToCents('9999999999.99'), 999999999999);
    expect(parseFundingRatio('NaN'), isNull);
    expect(parseFundingRatio('Infinity'), isNull);
    expect(parseFundingRatio(double.nan), isNull);
    expect(formatFundingPercent(1.2), '120%');
    expect(formatFundingPercent(-0.4), '0%');
    expect(withdrawNoteOrThrow('  hi  '), 'hi');
    expect(withdrawNoteOrThrow('n' * 500), 'n' * 500);
    expect(
      publicWalletError(const PostgrestException(
        message: 'milestone already settled',
        details: 'client_secret=abc',
      )),
      'milestone already settled',
    );
    expect(
      publicWalletError(const PostgrestException(
        message: 'Bearer leaked',
      )),
      'Could not update the goal wallet.',
    );
    expect(
      publicWalletError(const FunctionException(
        status: 409,
        details: {'error': 'withdraw exceeds captured balance'},
      )),
      'withdraw exceeds captured balance',
    );
    expect(
      publicWalletError(StateError('Bearer eyJhbGci secret')),
      'Could not update the goal wallet.',
    );
  });

  test('decline readback keeps the percent and the tail sums to the shortfall', () {
    final before = scheduleBeforeSnapshot();
    final after = scheduleSkippedSnapshot();
    expect(formatFundingPercent(before.fundingPercent), '40%');
    expect(formatFundingPercent(after.fundingPercent), '40%');
    expect(after.capturedAmount, '4.00');
    expect(after.goalAmount, before.goalAmount);
    expect(dateKey(after.goalDate), dateKey(before.goalDate));
    expect(scheduledCents(after.milestones), 600);
    expect(
      unfundedCents(goal: after.goalAmount, captured: after.capturedAmount),
      600,
    );
    final readback = readbackSchedule(
      before: before.milestones,
      after: after.milestones,
    );
    final changed = readback.rows.where((row) => row.previousAmount != null);
    expect(changed.map((row) => row.amount).toList(), ['3.00', '3.00']);
    expect(changed.map((row) => row.previousAmount).toList(), ['2.00', '2.00']);
    expect(readback.removed, isEmpty);
    expect(
      noticeAfter(before, after, skipped: true),
      'Skipped. Funded stayed 40%. Goal date stayed Nov 7, 2026.',
    );
  });

  test('approve readback does not capture and leaves the percent', () {
    final before = scheduleBeforeSnapshot();
    final after = scheduleApprovedSnapshot();
    expect(after.fundingPercent, before.fundingPercent);
    expect(after.capturedAmount, before.capturedAmount);
    expect(
      after.milestones.firstWhere((m) => m.id == openMilestoneId).status,
      'approved',
    );
    expect(
      noticeAfter(before, after, skipped: false),
      'Approved. Funded stayed 40%. No money was captured.',
    );
  });

  test('withdraw readback drops the percent and keeps the captured row', () {
    final before = withdrawBeforeSnapshot();
    final after = withdrawAfterSnapshot();
    expect(formatFundingPercent(before.fundingPercent), '40%');
    expect(formatFundingPercent(after.fundingPercent), '30%');
    expect(after.fundingPercent < before.fundingPercent, isTrue);
    expect(after.capturedAmount, before.capturedAmount);
    expect(after.withdrawnAmount, '1.00');
    expect(
      effectiveCapturedCents(
        captured: after.capturedAmount,
        withdrawn: after.withdrawnAmount,
      ),
      300,
    );
    expect(scheduledCents(after.milestones), 700);
    expect(
      unfundedCents(
        goal: after.goalAmount,
        captured: after.capturedAmount,
        withdrawn: after.withdrawnAmount,
      ),
      scheduledCents(after.milestones),
    );
    final readback = readbackSchedule(
      before: before.milestones,
      after: after.milestones,
    );
    expect(readback.removed, isEmpty);
    expect(
      readback.rows.map((row) => row.amount).toList(),
      ['4.00', '2.33', '2.33', '2.34'],
    );
    expect(
      noticeAfterWithdraw(before, after, '1.00'),
      'Took out \$1.00. Funded is 30%.',
    );
  });

  test('wallet client does not create orders or capture', () {
    final src = [
      'lib/services/goal_wallet.dart',
      'lib/features/parent/goal_wallet_screen.dart',
      'lib/features/kid/today_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    expect(src.contains('paypal-capture'), isFalse);
    expect(src.contains('paypal-order'), isFalse);
    expect(src.contains('PAYPAL_CLIENT_ID'), isFalse);
    expect(src.contains('PAYPAL_CLIENT_SECRET'), isFalse);
    expect(src.contains('print('), isFalse);
    expect(src.contains('funding-decline'), isTrue);
    expect(src.contains('wallet-withdraw'), isTrue);
    expect(src.contains('periodsLeft'), isFalse);
    expect(src.contains('splitShortfall'), isFalse);
    expect(src.contains('recomputeSchedule'), isFalse);
    final kid = File('lib/features/kid/today_screen.dart').readAsStringSync();
    expect(kid.contains('wallet-withdraw'), isFalse);
    expect(kid.contains('formatMoney('), isFalse);
    expect(kid.contains('formatUsd'), isFalse);
    expect(kid.contains('paypal_withdrawals'), isFalse);
  });

  testWidgets('approve marks the period and keeps 40 percent', (tester) async {
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterApprove: scheduleApprovedSnapshot(),
    );
    await _pumpWallet(tester, store);
    expect(_percentText(tester), '40%');
    expect(find.text('\$4.00 captured of \$10.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-dec')));
    await _frames(tester);
    expect(find.text('Approve this period?'), findsOneWidget);
    expect(find.textContaining('does not move money'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-approve')));
    await _frames(tester);

    expect(store.approvedId, openMilestoneId);
    expect(store.skippedId, isNull);
    expect(_percentText(tester), '40%');
    expect(find.byKey(const Key('wallet-notice')), findsOneWidget);
    expect(
      find.text('Approved. Funded stayed 40%. No money was captured.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approve-dec')), findsNothing);
    expect(find.text('Nov 7, 2026'), findsOneWidget);
  });

  testWidgets('cancel approve does not call the store', (tester) async {
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterApprove: scheduleApprovedSnapshot(),
    );
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('approve-dec')));
    await _frames(tester);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(store.approvedId, isNull);
    expect(find.byKey(const Key('approve-dec')), findsOneWidget);
  });

  testWidgets('skip leaves 40 percent and shows the server tail', (tester) async {
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterSkip: scheduleSkippedSnapshot(),
    );
    await _pumpWallet(tester, store);
    expect(_percentText(tester), '40%');

    await tester.tap(find.byKey(const Key('skip-dec')));
    await _frames(tester);
    expect(find.text('Skip this period?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-skip')));
    await _frames(tester);

    expect(store.skippedId, openMilestoneId);
    expect(store.approvedId, isNull);
    expect(_percentText(tester), '40%');
    expect(
      find.text('Skipped. Funded stayed 40%. Goal date stayed Nov 7, 2026.'),
      findsOneWidget,
    );
    expect(find.text('Still to fund \$6.00'), findsOneWidget);
    expect(find.text('Was \$2.00'), findsNWidgets(2));
    expect(find.text('\$3.00'), findsNWidgets(2));
    expect(find.text('Added nothing captured.'), findsNWidgets(2));
    expect(find.text('Nov 7, 2026'), findsOneWidget);
    expect(find.textContaining('taken off'), findsNothing);
    expect(scheduledCents(store.current!.milestones), 600);
  });

  testWidgets('a short wallet tells the parent and adds no later date',
      (tester) async {
    final store = MemoryWallet(current: shortWalletSnapshot());
    await _pumpWallet(tester, store);
    expect(find.byKey(const Key('wallet-short')), findsOneWidget);
    expect(find.textContaining('No period is left to cover it.'), findsOneWidget);
    expect(find.textContaining('No dates were added after it.'), findsOneWidget);
    expect(find.textContaining('has passed'), findsNothing);
    expect(find.text('Oct 21, 2026'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Unfunded \$5.00. On the schedule \$0.00.'), findsOneWidget);
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.byKey(const Key('wallet-withdraw')), findsNothing);
  });

  testWidgets('take-out drops the percent and shows the server periods',
      (tester) async {
    final store = MemoryWallet(
      current: withdrawBeforeSnapshot(),
      afterWithdraw: withdrawAfterSnapshot(),
    );
    await _pumpWallet(tester, store);
    expect(_percentText(tester), '40%');
    expect(find.text('\$4.00 captured of \$10.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await _frames(tester);
    expect(find.text('Take money out?'), findsOneWidget);
    expect(find.textContaining('PayPal is not charged again'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('withdraw-amount')), '1');
    await tester.enterText(find.byKey(const Key('withdraw-note')), 'field trip');
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await _frames(tester);

    expect(store.withdrawnAmount, '1.00');
    expect(store.withdrawnNote, 'field trip');
    expect(store.withdrawnWalletId, walletId);
    expect(_percentText(tester), '30%');
    expect(find.text('Took out \$1.00. Funded is 30%.'), findsOneWidget);
    expect(find.byKey(const Key('wallet-effective-captured')), findsOneWidget);
    expect(find.text('\$3.00 in the goal of \$10.00'), findsOneWidget);
    expect(
      find.text('Taken out \$1.00. Captured on the ledger is still \$4.00.'),
      findsOneWidget,
    );
    expect(find.text('Still to fund \$7.00'), findsOneWidget);
    expect(find.text('\$2.33'), findsNWidgets(2));
    expect(find.text('\$2.34'), findsOneWidget);
    expect(find.text('Was \$2.00'), findsOneWidget);
    expect(find.text('Was \$4.00'), findsOneWidget);
    expect(find.text('Oct 26, 2026'), findsOneWidget);
  });

  testWidgets('over-withdraw surfaces the error and leaves the percent',
      (tester) async {
    final store = MemoryWallet(
      current: withdrawBeforeSnapshot(),
      rejectWithdraw: true,
    );
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('withdraw-amount')), '5.00');
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await _frames(tester);

    expect(find.text('withdraw exceeds captured balance'), findsOneWidget);
    expect(_percentText(tester), '40%');
    expect(find.text('\$4.00 captured of \$10.00'), findsOneWidget);
    expect(find.text('\$2.33'), findsNothing);
    expect(store.current!.fundingPercent, 0.4);
    expect(store.withdrawnAmount, '5.00');
    await tester.pumpAndSettle();
  });

  testWidgets('a blank take-out amount stays in the dialog', (tester) async {
    final store = MemoryWallet(current: withdrawBeforeSnapshot());
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await _frames(tester);
    expect(find.text('Enter a dollar amount like 1.00.'), findsOneWidget);
    expect(store.withdrawnAmount, isNull);
    expect(_percentText(tester), '40%');
  });

  testWidgets('cancel take-out does not call the store', (tester) async {
    final store = MemoryWallet(current: withdrawBeforeSnapshot());
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await _frames(tester);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(store.withdrawnAmount, isNull);
    expect(find.byKey(const Key('wallet-withdraw')), findsOneWidget);
  });

  testWidgets('a failed approve leaves the percent and the period',
      (tester) async {
    final store = MemoryWallet(current: scheduleBeforeSnapshot());
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('approve-dec')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('confirm-approve')));
    await _frames(tester);

    expect(
      find.text('That period is no longer waiting for approval.'),
      findsOneWidget,
    );
    expect(_percentText(tester), '40%');
    expect(find.byKey(const Key('approve-dec')), findsOneWidget);
    expect(store.current!.fundingPercent, 0.4);
    expect(store.current!.capturedAmount, '4.00');
    await tester.pumpAndSettle();
  });

  testWidgets('a failed skip leaves the percent and the captured amount',
      (tester) async {
    final store = MemoryWallet(current: scheduleBeforeSnapshot());
    await _pumpWallet(tester, store);
    await tester.tap(find.byKey(const Key('skip-dec')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('confirm-skip')));
    await _frames(tester);

    expect(find.text('Could not update the goal wallet.'), findsOneWidget);
    expect(_percentText(tester), '40%');
    expect(find.byKey(const Key('skip-dec')), findsOneWidget);
    expect(store.current!.capturedAmount, '4.00');
    expect(find.text('Was \$2.00'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('a late reload does not undo a newer approve', (tester) async {
    final gates = <Completer<void>>[];
    addTearDown(() {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterApprove: scheduleApprovedSnapshot(),
      rejectWithdraw: true,
      loadPause: (loadNumber) async {
        if (loadNumber < 2) return;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      },
    );
    await _pumpWallet(tester, store);
    expect(_percentText(tester), '40%');

    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('withdraw-amount')), '5.00');
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await _frames(tester);

    expect(gates, hasLength(1));
    expect(find.text('withdraw exceeds captured balance'), findsOneWidget);
    expect(find.byKey(const Key('approve-dec')), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-dec')));
    await _frames(tester);
    await tester.tap(find.byKey(const Key('confirm-approve')));
    await _frames(tester);
    expect(find.byKey(const Key('approve-dec')), findsNothing);
    expect(_percentText(tester), '40%');

    gates.single.complete();
    await _frames(tester);

    expect(find.byKey(const Key('approve-dec')), findsNothing);
    expect(_percentText(tester), '40%');
    expect(
      find.text('Approved. Funded stayed 40%. No money was captured.'),
      findsOneWidget,
    );
    expect(store.approvedId, openMilestoneId);
    await tester.pumpAndSettle();
  });

  testWidgets('a thrown secret stays off the wallet screen', (tester) async {
    await _pumpWallet(
      tester,
      ThrowingWallet(error: StateError('Bearer eyJhbGci secret')),
    );
    expect(find.text('Could not update the goal wallet.'), findsOneWidget);
    expect(find.textContaining('Bearer'), findsNothing);
    expect(find.textContaining('eyJ'), findsNothing);
    expect(find.byKey(const Key('wallet-retry')), findsOneWidget);
  });

  testWidgets('load error can be retried and an empty wallet stays quiet',
      (tester) async {
    await _pumpWallet(tester, ThrowingWallet());
    expect(find.text('Could not read the goal wallet.'), findsOneWidget);
    expect(find.byKey(const Key('wallet-retry')), findsOneWidget);

    await _pumpWallet(tester, MemoryWallet(current: null));
    await _frames(tester);
    expect(find.byKey(const Key('wallet-empty')), findsOneWidget);
    expect(find.textContaining('\$'), findsNothing);
  });

  testWidgets('kid funded line is percent only, including the earned screen',
      (tester) async {
    final goal = _kidGoal(fundingPercent: 0.4);
    await tester.pumpWidget(_kidApp(goal, pct: 23));
    await tester.pump();

    expect(find.byKey(const Key('kid-funded-percent-g1')), findsOneWidget);
    expect(find.text('40% funded'), findsOneWidget);
    expect(find.byKey(const Key('wallet-withdraw')), findsNothing);
    _expectNoKidDollars(tester);

    await tester.pumpWidget(_kidApp(goal, pct: 100));
    await tester.pump();
    expect(find.text('You earned it.'), findsOneWidget);
    expect(find.text('40% funded'), findsOneWidget);
    _expectNoKidDollars(tester);

    await tester.pumpWidget(_kidApp(_kidGoal(fundingPercent: 0.3), pct: 23));
    await tester.pump();
    expect(find.text('30% funded'), findsOneWidget);
    expect(find.byKey(const Key('wallet-withdraw')), findsNothing);
    _expectNoKidDollars(tester);

    await tester.pumpWidget(_kidApp(_kidGoal(fundingPercent: 1.2), pct: 23));
    await tester.pump();
    expect(find.text('120% funded'), findsOneWidget);
    _expectNoKidDollars(tester);
  });

  testWidgets('kid screen omits the funded line when the percent is missing',
      (tester) async {
    await tester.pumpWidget(_kidApp(_kidGoal(), pct: 23));
    await tester.pump();
    expect(find.byKey(const Key('kid-funded-percent-g1')), findsNothing);
    _expectNoKidDollars(tester);
  });
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpWallet(WidgetTester tester, GoalWalletStore store) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: Dmc.theme(false),
    home: GoalWalletScreen(
      goalId: walletGoalId,
      goalTitle: 'Disneyland',
      store: store,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

String _percentText(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data!;
}

GoalProgressView _kidGoal({double? fundingPercent}) {
  return GoalProgressView(
    id: 'g1',
    title: 'Disneyland',
    targetAmount: 4242,
    goalMode: 'family_trip',
    allowMakeup: false,
    targetDate: DateTime(2026, 12, 1),
    weeksN: 8,
    choreProgressPct: 23,
    parentSaved: 1717,
    planWeightSum: 100,
    weeklyParentSave: 88.88,
    fundingPercent: fundingPercent,
  );
}

Widget _kidApp(GoalProgressView goal, {required double pct}) {
  return MaterialApp(
    theme: Dmc.theme(true),
    home: Scaffold(
      body: KidTodayBody(
        chores: const [],
        goals: [
          GoalProgressView(
            id: goal.id,
            title: goal.title,
            targetAmount: goal.targetAmount,
            goalMode: goal.goalMode,
            allowMakeup: goal.allowMakeup,
            targetDate: goal.targetDate,
            weeksN: goal.weeksN,
            weeksElapsed: goal.weeksElapsed,
            choreProgressPct: pct,
            parentSaved: goal.parentSaved,
            planWeightSum: goal.planWeightSum,
            weeklyParentSave: goal.weeklyParentSave,
            fundingPercent: goal.fundingPercent,
          ),
        ],
        now: DateTime(2026, 10, 19),
      ),
    ),
  );
}

void _expectNoKidDollars(WidgetTester tester) {
  expect(find.textContaining('\$'), findsNothing);
  expect(find.textContaining('4242'), findsNothing);
  expect(find.textContaining('1717'), findsNothing);
  expect(find.textContaining('88.88'), findsNothing);
  expect(find.textContaining('1,717'), findsNothing);
}
