import 'package:do_my_chore/services/goal_wallet.dart';

/// Canned rows copied from the funding-decline fixture in
/// supabase/functions/_shared/funding_schedule_test.ts
/// ("decline keeps the capture, writes a zero transfer, and resplits the shortfall").
/// Captured stays 4.00 of 10.00. The regenerated tail is 3.00 + 3.00.
/// This file does not split a shortfall.

const walletGoalId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const walletId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const capturedMilestoneId = 'cap';
const skippedEarlierId = 'skip';
const openMilestoneId = 'dec';
const laterProposedId = 'old';
const laterApprovedId = 'apr';
const regeneratedFirstId = 'n1';
const regeneratedSecondId = 'n2';

WalletMilestone _period({
  required String id,
  required int year,
  required int month,
  required int day,
  required String amount,
  required String status,
}) {
  return WalletMilestone(
    id: id,
    dueDate: DateTime(year, month, day),
    proposedAmount: amount,
    status: status,
  );
}

GoalWalletSnapshot walletSnapshot({
  required List<WalletMilestone> milestones,
  required String status,
  double fundingPercent = 0.4,
}) {
  return GoalWalletSnapshot(
    id: walletId,
    goalId: walletGoalId,
    goalAmount: '10.00',
    capturedAmount: '4.00',
    currency: 'USD',
    goalDate: DateTime(2026, 11, 7),
    status: status,
    fundingPercent: fundingPercent,
    milestones: milestones,
  );
}

List<WalletMilestone> scheduleBefore() => [
      _period(
        id: skippedEarlierId,
        year: 2026,
        month: 10,
        day: 5,
        amount: '1.00',
        status: 'skipped',
      ),
      _period(
        id: capturedMilestoneId,
        year: 2026,
        month: 10,
        day: 12,
        amount: '4.00',
        status: 'captured',
      ),
      _period(
        id: openMilestoneId,
        year: 2026,
        month: 10,
        day: 19,
        amount: '2.00',
        status: 'proposed',
      ),
      _period(
        id: laterProposedId,
        year: 2026,
        month: 10,
        day: 26,
        amount: '2.00',
        status: 'proposed',
      ),
      _period(
        id: laterApprovedId,
        year: 2026,
        month: 11,
        day: 2,
        amount: '2.00',
        status: 'approved',
      ),
    ];

GoalWalletSnapshot scheduleBeforeSnapshot() => walletSnapshot(
      milestones: scheduleBefore(),
      status: 'active',
    );

/// Approve marks the Oct 19 row. Captured money and the percent stay put.
GoalWalletSnapshot scheduleApprovedSnapshot() {
  final rows = [
    for (final row in scheduleBefore())
      if (row.id == openMilestoneId)
        WalletMilestone(
          id: row.id,
          dueDate: row.dueDate,
          proposedAmount: row.proposedAmount,
          status: 'approved',
        )
      else
        row,
  ];
  return walletSnapshot(milestones: rows, status: 'active');
}

/// Skip readback: Oct 19 is skipped, the old tail is gone, and the server
/// wrote 3.00 on Oct 26 and 3.00 on Nov 2. Percent is still 0.4.
GoalWalletSnapshot scheduleSkippedSnapshot() => walletSnapshot(
      milestones: [
        _period(
          id: skippedEarlierId,
          year: 2026,
          month: 10,
          day: 5,
          amount: '1.00',
          status: 'skipped',
        ),
        _period(
          id: capturedMilestoneId,
          year: 2026,
          month: 10,
          day: 12,
          amount: '4.00',
          status: 'captured',
        ),
        _period(
          id: openMilestoneId,
          year: 2026,
          month: 10,
          day: 19,
          amount: '2.00',
          status: 'skipped',
        ),
        _period(
          id: regeneratedFirstId,
          year: 2026,
          month: 10,
          day: 26,
          amount: '3.00',
          status: 'proposed',
        ),
        _period(
          id: regeneratedSecondId,
          year: 2026,
          month: 11,
          day: 2,
          amount: '3.00',
          status: 'proposed',
        ),
      ],
      status: 'active',
    );

/// Before a $1.00 take-out. Copied from the planWithdraw fixture
/// (goal 10.00, captured 4.00, proposed 2.00 and 4.00). Not split here.
GoalWalletSnapshot withdrawBeforeSnapshot() => walletSnapshot(
      milestones: [
        _period(
          id: capturedMilestoneId,
          year: 2026,
          month: 10,
          day: 12,
          amount: '4.00',
          status: 'captured',
        ),
        _period(
          id: 'mid',
          year: 2026,
          month: 10,
          day: 19,
          amount: '2.00',
          status: 'proposed',
        ),
        _period(
          id: 'later',
          year: 2026,
          month: 11,
          day: 2,
          amount: '4.00',
          status: 'proposed',
        ),
      ],
      status: 'active',
    );

/// Server readback after withdrawing 1.00 on 2026-10-17: percent 0.30,
/// future proposed rows 2.33, 2.33, 2.34. Amounts are the fixture, not a split.
GoalWalletSnapshot withdrawAfterSnapshot() => GoalWalletSnapshot(
      id: walletId,
      goalId: walletGoalId,
      goalAmount: '10.00',
      capturedAmount: '4.00',
      withdrawnAmount: '1.00',
      currency: 'USD',
      goalDate: DateTime(2026, 11, 7),
      status: 'active',
      fundingPercent: 0.3,
      milestones: [
        _period(
          id: capturedMilestoneId,
          year: 2026,
          month: 10,
          day: 12,
          amount: '4.00',
          status: 'captured',
        ),
        _period(
          id: 'p1',
          year: 2026,
          month: 10,
          day: 19,
          amount: '2.33',
          status: 'proposed',
        ),
        _period(
          id: 'p2',
          year: 2026,
          month: 10,
          day: 26,
          amount: '2.33',
          status: 'proposed',
        ),
        _period(
          id: 'p3',
          year: 2026,
          month: 11,
          day: 2,
          amount: '2.34',
          status: 'proposed',
        ),
      ],
    );

GoalWalletSnapshot shortWalletSnapshot() => GoalWalletSnapshot(
      id: walletId,
      goalId: walletGoalId,
      goalAmount: '5.00',
      capturedAmount: '0.00',
      currency: 'USD',
      goalDate: DateTime(2026, 10, 21),
      status: 'short',
      fundingPercent: 0,
      milestones: const [],
    );

class MemoryWallet implements GoalWalletStore {
  MemoryWallet({
    required this.current,
    this.afterApprove,
    this.afterSkip,
    this.afterWithdraw,
    this.rejectWithdraw = false,
    this.loadPause,
  });

  GoalWalletSnapshot? current;
  final GoalWalletSnapshot? afterApprove;
  final GoalWalletSnapshot? afterSkip;
  final GoalWalletSnapshot? afterWithdraw;
  final bool rejectWithdraw;

  /// Runs after this load's rows are captured. [loadNumber] starts at 1.
  final Future<void> Function(int loadNumber)? loadPause;
  String? approvedId;
  String? skippedId;
  String? withdrawnAmount;
  String? withdrawnNote;
  String? withdrawnWalletId;
  int loads = 0;

  @override
  Future<GoalWalletSnapshot?> load(String goalId) async {
    loads += 1;
    final snap = current;
    final pause = loadPause;
    if (pause != null) await pause(loads);
    if (snap == null || snap.goalId != goalId) return null;
    return snap;
  }

  @override
  Future<GoalWalletSnapshot> approve(String goalId, String milestoneId) async {
    approvedId = milestoneId;
    final next = afterApprove;
    if (next == null) {
      throw GoalWalletException('That period is no longer waiting for approval.');
    }
    current = next;
    return next;
  }

  @override
  Future<GoalWalletSnapshot> skip(String goalId, String milestoneId) async {
    skippedId = milestoneId;
    final next = afterSkip;
    if (next == null) {
      throw GoalWalletException('Could not update the goal wallet.');
    }
    current = next;
    return next;
  }

  @override
  Future<GoalWalletSnapshot> withdraw(
    String goalId,
    String walletId,
    String amount, {
    String note = '',
  }) async {
    withdrawnAmount = amount;
    withdrawnNote = note;
    withdrawnWalletId = walletId;
    if (rejectWithdraw) {
      throw GoalWalletException('withdraw exceeds captured balance');
    }
    final next = afterWithdraw;
    if (next == null) {
      throw GoalWalletException('Could not update the goal wallet.');
    }
    current = next;
    return next;
  }
}

class ThrowingWallet implements GoalWalletStore {
  ThrowingWallet({this.error});

  final Object? error;

  Object get _error =>
      error ?? GoalWalletException('Could not read the goal wallet.');

  @override
  Future<GoalWalletSnapshot?> load(String goalId) async => throw _error;

  @override
  Future<GoalWalletSnapshot> approve(String goalId, String milestoneId) async =>
      throw _error;

  @override
  Future<GoalWalletSnapshot> skip(String goalId, String milestoneId) async =>
      throw _error;

  @override
  Future<GoalWalletSnapshot> withdraw(
    String goalId,
    String walletId,
    String amount, {
    String note = '',
  }) async =>
      throw _error;
}
