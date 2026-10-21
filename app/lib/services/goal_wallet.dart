/// Parent Goal Wallet reads. Splits stay in `funding-decline` and
/// `wallet-withdraw`. This file displays rows and sends approve, skip, and
/// take-out. It does not invent dates or per-period amounts.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class GoalWalletException implements Exception {
  GoalWalletException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletMilestone {
  const WalletMilestone({
    required this.id,
    required this.dueDate,
    required this.proposedAmount,
    required this.status,
  });

  final String id;
  final DateTime dueDate;

  /// Canonical dollars from the server, two decimals, no currency sign.
  final String proposedAmount;

  /// proposed | approved | captured | skipped | declined
  final String status;
}

class GoalWalletSnapshot {
  const GoalWalletSnapshot({
    required this.id,
    required this.goalId,
    required this.goalAmount,
    required this.capturedAmount,
    this.withdrawnAmount = '0.00',
    required this.currency,
    required this.goalDate,
    required this.status,
    required this.fundingPercent,
    required this.milestones,
  });

  final String id;
  final String goalId;
  final String goalAmount;

  /// Sum of captured `paypal_transfers` only. Withdrawals are not folded in.
  final String capturedAmount;

  /// Sum of `paypal_withdrawals`. Kids never read this table.
  final String withdrawnAmount;
  final String currency;
  final DateTime goalDate;

  /// active | short | funded
  final String status;

  /// `goal_funding_percent`: effective captured / goal. Not recomputed here.
  final double fundingPercent;
  final List<WalletMilestone> milestones;
}

class ScheduleRow {
  const ScheduleRow({
    required this.id,
    required this.dueDate,
    required this.amount,
    required this.status,
    this.previousAmount,
  });

  final String id;
  final DateTime dueDate;
  final String amount;
  final String status;
  final String? previousAmount;
}

class RemovedPeriod {
  const RemovedPeriod({
    required this.dueDate,
    required this.amount,
    required this.status,
  });

  final DateTime dueDate;
  final String amount;
  final String status;
}

class ScheduleReadback {
  const ScheduleReadback({required this.rows, required this.removed});

  final List<ScheduleRow> rows;
  final List<RemovedPeriod> removed;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatDay(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

DateTime parseIsoDate(String raw) {
  final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final parts = date.split('-');
  if (parts.length != 3) {
    throw const FormatException('bad date');
  }
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final d = int.parse(parts[2]);
  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) {
    throw const FormatException('bad date');
  }
  return dt;
}

int moneyToCents(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.startsWith('-') || t.startsWith('+')) {
    throw const FormatException('bad amount');
  }
  final parts = t.split('.');
  if (parts.length > 2 || parts[0].isEmpty) {
    throw const FormatException('bad amount');
  }
  if (!RegExp(r'^\d+$').hasMatch(parts[0])) {
    throw const FormatException('bad amount');
  }
  final dollars = int.parse(parts[0]);
  // numeric(12,2) ceiling. Longer integer parts are not a wallet amount.
  if (dollars > 9999999999) throw const FormatException('bad amount');
  var cents = 0;
  if (parts.length == 2) {
    final frac = parts[1];
    if (!RegExp(r'^\d+$').hasMatch(frac)) {
      throw const FormatException('bad amount');
    }
    // Same rule as the server: extra digits are only trailing zeros.
    if (frac.length > 2 && RegExp(r'[1-9]').hasMatch(frac.substring(2))) {
      throw const FormatException('bad amount');
    }
    final head = frac.length >= 2 ? frac.substring(0, 2) : frac.padRight(2, '0');
    cents = int.parse(head);
  }
  return dollars * 100 + cents;
}

int centsFromServer(Object? value) {
  if (value is int) {
    if (value < 0) throw const FormatException('bad amount');
    return moneyToCents(value.toString());
  }
  if (value is num) {
    if (!value.isFinite) throw const FormatException('bad amount');
    // Round the binary residue to the two decimals numeric(12,2) stores.
    return moneyToCents(value.toStringAsFixed(2));
  }
  if (value is String) return moneyToCents(value);
  throw const FormatException('bad amount');
}

String canonicalFromCents(int cents) {
  if (cents < 0) throw const FormatException('bad amount');
  final dollars = cents ~/ 100;
  final rem = (cents % 100).toString().padLeft(2, '0');
  return '$dollars.$rem';
}

String canonicalMoney(Object? value) => canonicalFromCents(centsFromServer(value));

String formatUsdFromCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final rem = (abs % 100).toString().padLeft(2, '0');
  return '$sign\$$dollars.$rem';
}

String formatMoney(String canonical, String currency) {
  final cents = moneyToCents(canonical);
  if (currency == 'USD') return formatUsdFromCents(cents);
  return '$canonical $currency';
}

/// Whole percent when the ratio is within 0.05 of an integer, else one decimal.
/// Negative ratios display as 0%. Values above 1 stay above 100%.
String formatFundingPercent(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return '0%';
  final pct = ratio * 100;
  final nearest = pct.roundToDouble();
  if ((pct - nearest).abs() < 0.05) return '${nearest.toInt()}%';
  return '${pct.toStringAsFixed(1)}%';
}

double? parseFundingRatio(Object? raw) {
  if (raw is num) {
    if (!raw.isFinite) return null;
    return raw.toDouble();
  }
  if (raw is String) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }
  return null;
}

/// Display floor, same clamp as `goal_funding_percent`
/// (`greatest(0, captured - withdrawn)`). Does not choose period amounts.
int effectiveCapturedCents({
  required String captured,
  required String withdrawn,
}) {
  final net = moneyToCents(captured) - moneyToCents(withdrawn);
  return net < 0 ? 0 : net;
}

/// Goal column minus effective captured. Does not choose dates or rewrite periods.
int unfundedCents({
  required String goal,
  required String captured,
  String withdrawn = '0.00',
}) {
  final gap = moneyToCents(goal) -
      effectiveCapturedCents(captured: captured, withdrawn: withdrawn);
  return gap < 0 ? 0 : gap;
}

/// Strips a leading dollar sign and thousands separators before parsing.
String normalizeAmountInput(String raw) {
  var t = raw.trim();
  if (t.startsWith('\$')) t = t.substring(1).trim();
  return t.replaceAll(',', '');
}

String withdrawAmountOrThrow(String amount) {
  final String canonical;
  try {
    canonical = canonicalMoney(normalizeAmountInput(amount));
  } on FormatException {
    throw GoalWalletException('Enter a dollar amount like 1.00.');
  }
  if (moneyToCents(canonical) <= 0) {
    throw GoalWalletException('Enter an amount greater than zero.');
  }
  return canonical;
}

String withdrawNoteOrThrow(String note) {
  final trimmed = note.trim();
  if (trimmed.length > 500) {
    throw GoalWalletException('Note must be 500 characters or fewer.');
  }
  return trimmed;
}

/// Sum of server rows still open (proposed or approved).
int scheduledCents(List<WalletMilestone> milestones) {
  var sum = 0;
  for (final m in milestones) {
    if (m.status == 'proposed' || m.status == 'approved') {
      sum += moneyToCents(m.proposedAmount);
    }
  }
  return sum;
}

bool sameMoney(String a, String b) => moneyToCents(a) == moneyToCents(b);

ScheduleReadback readbackSchedule({
  required List<WalletMilestone> before,
  required List<WalletMilestone> after,
}) {
  final prevByDate = <String, WalletMilestone>{
    for (final m in before) dateKey(m.dueDate): m,
  };
  final afterDates = after.map((m) => dateKey(m.dueDate)).toSet();
  final rows = <ScheduleRow>[];
  for (final m in after) {
    final prev = prevByDate[dateKey(m.dueDate)];
    final changed = prev != null && !sameMoney(prev.proposedAmount, m.proposedAmount);
    rows.add(ScheduleRow(
      id: m.id,
      dueDate: m.dueDate,
      amount: m.proposedAmount,
      status: m.status,
      previousAmount: changed ? prev.proposedAmount : null,
    ));
  }
  final removed = <RemovedPeriod>[
    for (final m in before)
      if (!afterDates.contains(dateKey(m.dueDate)))
        RemovedPeriod(
          dueDate: m.dueDate,
          amount: m.proposedAmount,
          status: m.status,
        ),
  ];
  return ScheduleReadback(rows: rows, removed: removed);
}

String milestoneStatusLabel(String status) {
  switch (status) {
    case 'proposed':
      return 'Proposed';
    case 'approved':
      return 'Approved';
    case 'captured':
      return 'Captured';
    case 'skipped':
      return 'Skipped';
    case 'declined':
      return 'Declined';
    default:
      return 'Unknown';
  }
}

String? milestoneFootnote(String status) {
  switch (status) {
    case 'skipped':
    case 'declined':
      return 'Added nothing captured.';
    case 'captured':
      return 'Captured into the goal.';
    default:
      return null;
  }
}

String noticeAfter(
  GoalWalletSnapshot before,
  GoalWalletSnapshot after, {
  required bool skipped,
}) {
  final pct = formatFundingPercent(after.fundingPercent);
  final day = formatDay(after.goalDate);
  final pctSame = formatFundingPercent(before.fundingPercent) == pct;
  final dateSame = dateKey(before.goalDate) == dateKey(after.goalDate);
  if (skipped && pctSame && dateSame) {
    return 'Skipped. Funded stayed $pct. Goal date stayed $day.';
  }
  if (skipped) {
    return 'Skipped. Funded is $pct. Goal date is $day.';
  }
  if (pctSame) {
    return 'Approved. Funded stayed $pct. No money was captured.';
  }
  return 'Approved. Funded is $pct. No money was captured.';
}

String noticeAfterWithdraw(
  GoalWalletSnapshot before,
  GoalWalletSnapshot after,
  String amount,
) {
  final pct = formatFundingPercent(after.fundingPercent);
  final taken = formatMoney(canonicalMoney(amount), after.currency);
  if (formatFundingPercent(before.fundingPercent) == pct) {
    return 'Took out $taken. Funded stayed $pct.';
  }
  return 'Took out $taken. Funded is $pct.';
}

String publicWalletError(Object? raw) {
  final text = _errorText(raw).trim();
  final lower = text.toLowerCase();
  const blocked = [
    'secret',
    'bearer',
    'client_id',
    'client_secret',
    'paypal_client',
    'access_token',
    'authorization',
    'apikey',
    'api_key',
    'eyj',
  ];
  if (text.isEmpty ||
      text.length > 160 ||
      blocked.any(lower.contains) ||
      text.contains('\$')) {
    return 'Could not update the goal wallet.';
  }
  return text;
}

String _errorText(Object? raw) {
  if (raw is GoalWalletException) return raw.message;
  if (raw is PostgrestException) return raw.message;
  if (raw is FunctionException) return _errorText(raw.details);
  if (raw is Map) {
    final error = raw['error'];
    if (error != null) return _errorText(error);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded['error'] != null) {
          return _errorText(decoded['error']);
        }
      } catch (_) {
        return trimmed;
      }
    }
    return trimmed;
  }
  return '';
}

abstract class GoalWalletStore {
  Future<GoalWalletSnapshot?> load(String goalId);
  Future<GoalWalletSnapshot> approve(String goalId, String milestoneId);
  Future<GoalWalletSnapshot> skip(String goalId, String milestoneId);

  /// Posts `wallet-withdraw`, then reloads rows. The returned milestones are
  /// whatever the server wrote, not a client-side split.
  Future<GoalWalletSnapshot> withdraw(
    String goalId,
    String walletId,
    String amount, {
    String note = '',
  });
}

class SupabaseGoalWalletStore implements GoalWalletStore {
  SupabaseGoalWalletStore(this._parent);

  final SupabaseClient _parent;

  @override
  Future<GoalWalletSnapshot?> load(String goalId) => _guard(() => _load(goalId));

  @override
  Future<GoalWalletSnapshot> approve(String goalId, String milestoneId) =>
      _guard(() async {
        final rows = await _parent
            .from('funding_milestones')
            .update({'status': 'approved'})
            .eq('id', milestoneId)
            .eq('status', 'proposed')
            .select('id');
        if (rows.isEmpty) {
          throw GoalWalletException(
            'That period is no longer waiting for approval.',
          );
        }
        final next = await _load(goalId);
        if (next == null) {
          throw GoalWalletException('Goal wallet disappeared after approve.');
        }
        return next;
      });

  @override
  Future<GoalWalletSnapshot> skip(String goalId, String milestoneId) =>
      _guard(() async {
        await _decline(milestoneId);
        final next = await _load(goalId);
        if (next == null) {
          throw GoalWalletException('Goal wallet disappeared after skip.');
        }
        return next;
      });

  @override
  Future<GoalWalletSnapshot> withdraw(
    String goalId,
    String walletId,
    String amount, {
    String note = '',
  }) =>
      _guard(() async {
        if (walletId.isEmpty) {
          throw GoalWalletException('Could not update the goal wallet.');
        }
        final canonical = withdrawAmountOrThrow(amount);
        final cleanNote = withdrawNoteOrThrow(note);
        await _postWithdraw(walletId, canonical, cleanNote);
        final next = await _load(goalId);
        if (next == null) {
          throw GoalWalletException('Goal wallet disappeared after take-out.');
        }
        return next;
      });

  Future<GoalWalletSnapshot?> _load(String goalId) async {
    final wallets = await _parent
        .from('goal_wallets')
        .select('id,goal_id,goal_amount,currency,goal_date,status')
        .eq('goal_id', goalId)
        .limit(1);
    if (wallets.isEmpty) return null;
    final wallet = Map<String, dynamic>.from(wallets.first as Map);
    final walletId = wallet['id'];
    if (walletId is! String || walletId.isEmpty) {
      throw GoalWalletException('Could not read the goal wallet.');
    }
    final milestones = await _parent
        .from('funding_milestones')
        .select('id,due_date,proposed_amount,status')
        .eq('wallet_id', walletId)
        .order('due_date');
    final transfers = await _parent
        .from('paypal_transfers')
        .select('amount,status')
        .eq('wallet_id', walletId)
        .eq('status', 'captured');
    final withdrawals = await _parent
        .from('paypal_withdrawals')
        .select('amount')
        .eq('wallet_id', walletId);
    final pctRaw = await _parent.rpc(
      'goal_funding_percent',
      params: {'p_goal_id': goalId},
    );
    return _snapshot(
      wallet: wallet,
      milestones: milestones,
      transfers: transfers,
      withdrawals: withdrawals,
      pctRaw: pctRaw,
    );
  }

  Future<void> _postWithdraw(String walletId, String amount, String note) async {
    try {
      final res = await _parent.functions.invoke(
        'wallet-withdraw',
        body: {
          'wallet_id': walletId,
          'amount': amount,
          'note': note,
        },
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw GoalWalletException(publicWalletError(data['error']));
      }
      if (data is! Map || data['funding_percent'] == null) {
        throw GoalWalletException('Funding service did not return a percent.');
      }
    } on GoalWalletException {
      rethrow;
    } on FunctionException catch (e) {
      throw GoalWalletException(publicWalletError(e));
    }
  }

  Future<void> _decline(String milestoneId) async {
    try {
      final res = await _parent.functions.invoke(
        'funding-decline',
        body: {
          'milestone_id': milestoneId,
          'decision': 'skipped',
        },
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw GoalWalletException(publicWalletError(data['error']));
      }
      if (data is! Map || data['funding_percent'] == null) {
        throw GoalWalletException('Funding service did not return a percent.');
      }
    } on GoalWalletException {
      rethrow;
    } on FunctionException catch (e) {
      throw GoalWalletException(publicWalletError(e));
    }
  }

  GoalWalletSnapshot _snapshot({
    required Map<String, dynamic> wallet,
    required Object milestones,
    required Object transfers,
    required Object withdrawals,
    required Object? pctRaw,
  }) {
    final ratio = parseFundingRatio(pctRaw);
    if (ratio == null) {
      throw GoalWalletException('Could not read the funded percent.');
    }
    final goalId = wallet['goal_id'];
    final goalDate = wallet['goal_date'];
    final status = wallet['status'];
    if (goalId is! String || goalDate is! String || status is! String) {
      throw GoalWalletException('Could not read the goal wallet.');
    }
    if (milestones is! Iterable ||
        transfers is! Iterable ||
        withdrawals is! Iterable) {
      throw GoalWalletException('Could not read the goal wallet.');
    }
    var captured = 0;
    for (final row in transfers) {
      if (row is! Map) continue;
      if (row['status'] != 'captured') continue;
      captured += centsFromServer(row['amount']);
    }
    var withdrawn = 0;
    for (final row in withdrawals) {
      if (row is! Map) {
        throw GoalWalletException('Could not read a take-out.');
      }
      withdrawn += centsFromServer(row['amount']);
    }
    final parsed = <WalletMilestone>[];
    for (final row in milestones) {
      if (row is! Map) {
        throw GoalWalletException('Could not read a funding period.');
      }
      final id = row['id'];
      final due = row['due_date'];
      final milestoneStatus = row['status'];
      if (id is! String || due is! String || milestoneStatus is! String) {
        throw GoalWalletException('Could not read a funding period.');
      }
      parsed.add(WalletMilestone(
        id: id,
        dueDate: parseIsoDate(due),
        proposedAmount: canonicalMoney(row['proposed_amount']),
        status: milestoneStatus,
      ));
    }
    return GoalWalletSnapshot(
      id: wallet['id'] as String,
      goalId: goalId,
      goalAmount: canonicalMoney(wallet['goal_amount']),
      capturedAmount: canonicalFromCents(captured),
      withdrawnAmount: canonicalFromCents(withdrawn),
      currency: wallet['currency'] is String ? wallet['currency'] as String : 'USD',
      goalDate: parseIsoDate(goalDate),
      status: status,
      fundingPercent: ratio,
      milestones: parsed,
    );
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on GoalWalletException {
      rethrow;
    } on FormatException {
      throw GoalWalletException('Could not read the goal wallet.');
    } catch (e) {
      throw GoalWalletException(publicWalletError(e));
    }
  }
}
