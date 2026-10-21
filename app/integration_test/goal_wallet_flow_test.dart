import 'package:do_my_chore/core/dmc_theme.dart';
import 'package:do_my_chore/features/parent/goal_wallet_screen.dart';
import 'package:do_my_chore/services/goal_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/goal_wallet_harness.dart';

Future<void> _shot(IntegrationTestWidgetsFlutterBinding binding, String name) async {
  await binding.convertFlutterSurfaceToImage();
  await binding.takeScreenshot(name);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('approve keeps the funded percent', (tester) async {
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterApprove: scheduleApprovedSnapshot(),
    );
    await tester.pumpWidget(MaterialApp(
      theme: Dmc.theme(false),
      home: GoalWalletScreen(
        goalId: walletGoalId,
        goalTitle: 'Disneyland',
        store: store,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('approve-dec')),
      200,
    );
    await tester.tap(find.byKey(const Key('approve-dec')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-approve')));
    await tester.pumpAndSettle();
    expect(store.approvedId, openMilestoneId);
    expect(find.text('Approved. Funded stayed 40%. No money was captured.'), findsOneWidget);
    expect(find.text('40%'), findsWidgets);
    await _shot(binding, 'goal-wallet-approve');
  });

  testWidgets('decline leaves the funded percent and shows the new tail', (tester) async {
    final store = MemoryWallet(
      current: scheduleBeforeSnapshot(),
      afterSkip: scheduleSkippedSnapshot(),
    );
    await tester.pumpWidget(MaterialApp(
      theme: Dmc.theme(false),
      home: GoalWalletScreen(
        goalId: walletGoalId,
        goalTitle: 'Disneyland',
        store: store,
      ),
    ));
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data;
    await tester.scrollUntilVisible(
      find.byKey(const Key('skip-dec')),
      200,
    );
    await tester.tap(find.byKey(const Key('skip-dec')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-skip')));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data;
    expect(before, '40%');
    expect(after, before);
    expect(find.text('Still to fund \$6.00'), findsOneWidget);
    expect(find.text('Was \$2.00'), findsWidgets);
    expect(scheduledCents(store.current!.milestones), 600);
    await _shot(binding, 'goal-wallet-decline');
  });

  testWidgets('take-out drops the percent and shows the new periods', (tester) async {
    final store = MemoryWallet(
      current: withdrawBeforeSnapshot(),
      afterWithdraw: withdrawAfterSnapshot(),
    );
    await tester.pumpWidget(MaterialApp(
      theme: Dmc.theme(false),
      home: GoalWalletScreen(
        goalId: walletGoalId,
        goalTitle: 'Disneyland',
        store: store,
      ),
    ));
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data;
    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('withdraw-amount')), '1.00');
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data;
    expect(before, '40%');
    expect(after, '30%');
    expect(find.text('\$2.33'), findsWidgets);
    expect(find.text('\$2.34'), findsOneWidget);
    expect(find.text('Still to fund \$7.00'), findsOneWidget);
    await _shot(binding, 'goal-wallet-withdraw');
  });

  testWidgets('over-withdraw shows an error and leaves the percent', (tester) async {
    final store = MemoryWallet(
      current: withdrawBeforeSnapshot(),
      rejectWithdraw: true,
    );
    await tester.pumpWidget(MaterialApp(
      theme: Dmc.theme(false),
      home: GoalWalletScreen(
        goalId: walletGoalId,
        goalTitle: 'Disneyland',
        store: store,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wallet-withdraw')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('withdraw-amount')), '5.00');
    await tester.tap(find.byKey(const Key('confirm-withdraw')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('withdraw exceeds captured balance'), findsOneWidget);
    final after = tester.widget<Text>(find.byKey(const Key('wallet-funded-percent'))).data;
    expect(after, '40%');
    await _shot(binding, 'goal-wallet-over-withdraw');
    await tester.pumpAndSettle();
  });
}
