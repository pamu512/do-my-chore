import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/goal_wallet.dart';

/// Parent funding schedule. Dollars stay on this screen. Approve marks a
/// period; skip calls `funding-decline`; take-out calls `wallet-withdraw`.
/// Later periods are the rows those calls wrote back.
class GoalWalletScreen extends StatefulWidget {
  const GoalWalletScreen({
    super.key,
    required this.goalId,
    required this.goalTitle,
    required this.store,
  });

  final String goalId;
  final String goalTitle;
  final GoalWalletStore store;

  @override
  State<GoalWalletScreen> createState() => _GoalWalletScreenState();
}

class _GoalWalletScreenState extends State<GoalWalletScreen> {
  bool _loading = true;
  String? _error;
  String? _busyId;
  bool _takingOut = false;
  String? _notice;
  GoalWalletSnapshot? _snapshot;
  List<WalletMilestone>? _before;

  /// Bumped on every load or parent action. A finishing call ignores itself
  /// when a later one has already taken the screen.
  int _op = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GoalWalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goalId != widget.goalId || oldWidget.store != widget.store) {
      _snapshot = null;
      _error = null;
      _before = null;
      _notice = null;
      _busyId = null;
      _load();
    }
  }

  Future<void> _load() async {
    final op = ++_op;
    // Initial _loading is already true. setState here would run inside initState.
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final next = await widget.store.load(widget.goalId);
      if (!mounted || op != _op) return;
      setState(() {
        _snapshot = next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || op != _op) return;
      setState(() {
        _loading = false;
        _error = _visibleError(e);
      });
    }
  }

  Future<void> _run(
    String milestoneId,
    Future<GoalWalletSnapshot> Function() action, {
    required bool skipped,
  }) async {
    final before = _snapshot;
    final op = ++_op;
    setState(() => _busyId = milestoneId);
    try {
      final after = await action();
      if (!mounted || op != _op) return;
      setState(() {
        _busyId = null;
        _before = before?.milestones;
        _snapshot = after;
        _notice = before == null
            ? null
            : noticeAfter(before, after, skipped: skipped);
        _error = null;
      });
    } catch (e) {
      if (!mounted || op != _op) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_visibleError(e))),
      );
      await _reloadKeeping(op);
    }
  }

  Future<void> _reloadKeeping(int op) async {
    try {
      final next = await widget.store.load(widget.goalId);
      if (!mounted || op != _op) return;
      setState(() => _snapshot = next);
    } catch (_) {
      // The snackbar already says what failed.
    }
  }

  bool get _locked => _busyId != null || _takingOut;

  Future<void> _takeOut() async {
    if (_locked) return;
    final snap = _snapshot;
    if (snap == null) return;
    final available = effectiveCapturedCents(
      captured: snap.capturedAmount,
      withdrawn: snap.withdrawnAmount,
    );
    if (available <= 0) return;
    final result = await showDialog<_TakeOutResult>(
      context: context,
      builder: (context) => _TakeOutDialog(currency: snap.currency),
    );
    if (result == null || !mounted) return;
    final before = snap;
    final op = ++_op;
    setState(() => _takingOut = true);
    try {
      final after = await widget.store.withdraw(
        widget.goalId,
        snap.id,
        result.amount,
        note: result.note,
      );
      if (!mounted || op != _op) return;
      setState(() {
        _takingOut = false;
        _before = before.milestones;
        _snapshot = after;
        _notice = noticeAfterWithdraw(before, after, result.amount);
        _error = null;
      });
    } catch (e) {
      if (!mounted || op != _op) return;
      setState(() => _takingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_visibleError(e))),
      );
      await _reloadKeeping(op);
    }
  }

  Future<void> _approve(WalletMilestone milestone) async {
    if (_locked) return;
    final snap = _snapshot;
    if (snap == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve this period?'),
        content: Text(
          'Marks ${formatDay(milestone.dueDate)} for ${formatMoney(milestone.proposedAmount, snap.currency)}. '
          'The goal date stays ${formatDay(snap.goalDate)}. This does not move money.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-approve'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      milestone.id,
      () => widget.store.approve(widget.goalId, milestone.id),
      skipped: false,
    );
  }

  Future<void> _skip(WalletMilestone milestone) async {
    if (_locked) return;
    final snap = _snapshot;
    if (snap == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip this period?'),
        content: Text(
          'The ${formatDay(milestone.dueDate)} period of ${formatMoney(milestone.proposedAmount, snap.currency)} adds nothing captured. '
          'The goal date stays ${formatDay(snap.goalDate)}. Later periods are updated from what is still unfunded.',
          style: const TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-skip'),
            style: FilledButton.styleFrom(backgroundColor: Dmc.clay),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Skip this period'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      milestone.id,
      () => widget.store.skip(widget.goalId, milestone.id),
      skipped: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goal wallet')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Semantics(
        label: 'Loading goal wallet',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: const [
            DmcSkeleton(height: 22, width: 180),
            SizedBox(height: 16),
            DmcGoalCardSkeleton(),
          ],
        ),
      );
    }
    if (_error != null && _snapshot == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(widget.goalTitle, style: Dmc.displayStyle(size: 22, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('wallet-retry'),
            onPressed: _load,
            child: const Text('Try again'),
          ),
        ],
      );
    }
    final snap = _snapshot;
    if (snap == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(widget.goalTitle, style: Dmc.displayStyle(size: 22, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
            'No funding schedule for this goal yet.',
            key: Key('wallet-empty'),
            style: TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
          ),
        ],
      );
    }
    final readback = _before == null
        ? null
        : readbackSchedule(before: _before!, after: snap.milestones);
    final previousById = {
      for (final row in readback?.rows ?? const <ScheduleRow>[]) row.id: row,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(widget.goalTitle, style: Dmc.displayStyle(size: 22, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        _summary(snap),
        if (_notice != null) ...[
          const SizedBox(height: 10),
          _note(_notice!),
        ],
        if (snap.status == 'short') ...[
          const SizedBox(height: 10),
          _shortBanner(snap),
        ],
        if (_locked) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
        const SizedBox(height: 16),
        Text('PERIODS', style: Dmc.micro),
        const SizedBox(height: 8),
        if (snap.milestones.isEmpty)
          const Text(
            'No periods on this wallet.',
            style: TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < snap.milestones.length; i++)
                  _period(
                    snap,
                    snap.milestones[i],
                    previousById[snap.milestones[i].id],
                    showDivider: i > 0,
                  ),
              ],
            ),
          ),
        if (readback != null)
          for (final gone in readback.removed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${formatDay(gone.dueDate)} was taken off the schedule. It was ${formatMoney(gone.amount, snap.currency)}.',
                style: const TextStyle(fontSize: 13, height: 1.4, color: Dmc.ink2),
              ),
            ),
      ],
    );
  }

  Widget _summary(GoalWalletSnapshot snap) {
    final unfunded = unfundedCents(
      goal: snap.goalAmount,
      captured: snap.capturedAmount,
      withdrawn: snap.withdrawnAmount,
    );
    final scheduled = scheduledCents(snap.milestones);
    final funded = formatFundingPercent(snap.fundingPercent);
    final effective = effectiveCapturedCents(
      captured: snap.capturedAmount,
      withdrawn: snap.withdrawnAmount,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GOAL DATE', style: Dmc.micro),
            const SizedBox(height: 4),
            Text(
              formatDay(snap.goalDate),
              key: const Key('wallet-goal-date'),
              style: Dmc.displayStyle(size: 18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              funded,
              key: const Key('wallet-funded-percent'),
              style: Dmc.displayStyle(size: 40, weight: FontWeight.w700, color: Dmc.pine),
            ),
            const Text(
              'funded',
              style: TextStyle(fontSize: 14, color: Dmc.ink2),
            ),
            const SizedBox(height: 8),
            _capturedLine(snap),
            const SizedBox(height: 4),
            _stillToFund(unfunded, scheduled, snap.currency),
            if (effective > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('wallet-withdraw'),
                  style: FilledButton.styleFrom(backgroundColor: Dmc.clay),
                  onPressed: _locked ? null : _takeOut,
                  child: const Text('Take money out'),
                ),
              ),
            ],
            if (moneyToCents(snap.capturedAmount) > 0) ...[
              const SizedBox(height: 8),
              const Text(
                'Captured amounts are on the parent save log.',
                style: TextStyle(fontSize: 13, height: 1.4, color: Dmc.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _capturedLine(GoalWalletSnapshot snap) {
    final gross = formatMoney(snap.capturedAmount, snap.currency);
    final goal = formatMoney(snap.goalAmount, snap.currency);
    final style = const TextStyle(fontSize: 14, height: 1.4, color: Dmc.ink2);
    if (moneyToCents(snap.withdrawnAmount) == 0) {
      return Text('$gross captured of $goal', style: style);
    }
    final inGoal = formatMoney(
      canonicalFromCents(effectiveCapturedCents(
        captured: snap.capturedAmount,
        withdrawn: snap.withdrawnAmount,
      )),
      snap.currency,
    );
    final taken = formatMoney(snap.withdrawnAmount, snap.currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$inGoal in the goal of $goal',
          key: const Key('wallet-effective-captured'),
          style: style,
        ),
        const SizedBox(height: 2),
        Text(
          'Taken out $taken. Captured on the ledger is still $gross.',
          key: const Key('wallet-withdrawn'),
          style: style,
        ),
      ],
    );
  }

  Widget _stillToFund(int unfunded, int scheduled, String currency) {
    if (unfunded == 0) {
      return const Text(
        'Nothing left to fund.',
        key: Key('wallet-funded-done'),
        style: TextStyle(fontSize: 14, height: 1.4, color: Dmc.ink),
      );
    }
    final unfundedLabel = formatMoney(canonicalFromCents(unfunded), currency);
    if (scheduled == unfunded) {
      return Text(
        'Still to fund $unfundedLabel',
        key: const Key('still-to-fund'),
        style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: Dmc.ink),
      );
    }
    final scheduledLabel = formatMoney(canonicalFromCents(scheduled), currency);
    return Text(
      'Unfunded $unfundedLabel. On the schedule $scheduledLabel.',
      key: const Key('still-to-fund'),
      style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: Dmc.ink),
    );
  }

  Widget _note(String text) {
    return Container(
      key: const Key('wallet-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Dmc.pineSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Dmc.line),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: Dmc.pineDeep),
      ),
    );
  }

  Widget _shortBanner(GoalWalletSnapshot snap) {
    final unfunded = unfundedCents(
      goal: snap.goalAmount,
      captured: snap.capturedAmount,
      withdrawn: snap.withdrawnAmount,
    );
    return Container(
      key: const Key('wallet-short'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Dmc.claySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8CFC7)),
      ),
      child: Text(
        'Goal is short ${formatMoney(canonicalFromCents(unfunded), snap.currency)}. '
        'No period is left to cover it. No dates were added after it.',
        style: const TextStyle(fontSize: 13.5, height: 1.4, color: Dmc.clayText),
      ),
    );
  }

  Widget _period(
    GoalWalletSnapshot snap,
    WalletMilestone milestone,
    ScheduleRow? row,
    {required bool showDivider}
  ) {
    final previous = row?.previousAmount;
    final canApprove = milestone.status == 'proposed' && !_locked;
    final canSkip = (milestone.status == 'proposed' || milestone.status == 'approved') &&
        !_locked;
    final day = formatDay(milestone.dueDate);
    final pastGoal = milestone.dueDate.isAfter(snap.goalDate);
    return Container(
      key: Key('period-${milestone.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: showDivider ? const Border(top: BorderSide(color: Dmc.line)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Dmc.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(milestone.proposedAmount, snap.currency),
                style: Dmc.displayStyle(size: 18, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            milestoneStatusLabel(milestone.status),
            style: const TextStyle(fontSize: 13, color: Dmc.ink2),
          ),
          if (milestoneFootnote(milestone.status) != null)
            Text(
              milestoneFootnote(milestone.status)!,
              style: const TextStyle(fontSize: 13, height: 1.35, color: Dmc.muted),
            ),
          if (previous != null)
            Text(
              'Was ${formatMoney(previous, snap.currency)}',
              style: const TextStyle(fontSize: 13, height: 1.35, color: Dmc.ink),
            ),
          if (pastGoal)
            Text(
              'This date is after the goal date.',
              style: const TextStyle(fontSize: 13, height: 1.35, color: Dmc.clayText),
            ),
          if (canApprove) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: Key('approve-${milestone.id}'),
                onPressed: () => _approve(milestone),
                child: Text('Approve $day'),
              ),
            ),
          ],
          if (canSkip) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: Key('skip-${milestone.id}'),
                onPressed: () => _skip(milestone),
                child: Text('Skip $day'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _visibleError(Object error) {
  if (error is GoalWalletException) return error.message;
  return publicWalletError(error);
}

class _TakeOutResult {
  const _TakeOutResult({required this.amount, required this.note});

  final String amount;
  final String note;
}

class _TakeOutDialog extends StatefulWidget {
  const _TakeOutDialog({required this.currency});

  final String currency;

  @override
  State<_TakeOutDialog> createState() => _TakeOutDialogState();
}

class _TakeOutDialogState extends State<_TakeOutDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _amountError;
  String? _noteError;
  bool _closed = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closed || !mounted) return;
    String? canonical;
    String? note;
    String? amountError;
    String? noteError;
    try {
      canonical = withdrawAmountOrThrow(_amount.text);
    } on GoalWalletException catch (e) {
      amountError = e.message;
    }
    try {
      note = withdrawNoteOrThrow(_note.text);
    } on GoalWalletException catch (e) {
      noteError = e.message;
    }
    if (canonical == null || note == null) {
      setState(() {
        _amountError = amountError;
        _noteError = noteError;
      });
      return;
    }
    _closed = true;
    Navigator.pop(
      context,
      _TakeOutResult(amount: canonical, note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Take money out?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Records money you already spent. PayPal is not charged again. Later periods come back from the server.',
              style: TextStyle(fontSize: 14, height: 1.45, color: Dmc.ink2),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('withdraw-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: widget.currency == 'USD' ? '\$' : null,
                errorText: _amountError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('withdraw-note'),
              controller: _note,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Note, optional',
                errorText: _noteError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-withdraw'),
          style: FilledButton.styleFrom(backgroundColor: Dmc.clay),
          onPressed: _submit,
          child: const Text('Take out'),
        ),
      ],
    );
  }
}
