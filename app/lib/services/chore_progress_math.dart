/// Chore progress math for the rev 3 money model.
///
/// Kid earns 100% of the goal through weighted chores. Each chore has a
/// cadence (once | daily | weekly) and a weight_pct; the per-approval credit
/// is weight_pct / expected_instances, where expected instances are once = 1,
/// weekly = N, daily = 7 * N (POC: no calendar-day counting). Weights may sum
/// above 100% (oversubscribe); the kid bar caps at 100%.
///
/// No Flutter imports: this library is pure and unit-testable.
library;

import 'dart:math';

/// Whole weeks from [today] to [targetDate]; ceil of days/7, minimum 1.
int weeksRemaining({required DateTime today, required DateTime targetDate}) {
  final days = targetDate.difference(today).inDays;
  final weeks = (days / 7).ceil();
  return weeks < 1 ? 1 : weeks;
}

/// Planned instances of [cadence] until the target date.
/// once -> 1, weekly -> N, daily -> 7 * N. N below 1 clamps to 1.
int expectedInstances({required String cadence, required int weeksN}) {
  final n = weeksN < 1 ? 1 : weeksN;
  switch (cadence) {
    case 'once':
      return 1;
    case 'weekly':
      return n;
    case 'daily':
      return 7 * n;
    default:
      throw ArgumentError('unknown cadence: $cadence');
  }
}

/// Credit toward the 100% bar for one approved instance.
double instanceCreditPct({
  required double weightPct,
  required int expectedInstances,
}) {
  if (expectedInstances <= 0) return 0;
  return weightPct / expectedInstances;
}

/// Kid progress: sum of approved instance credits, capped at 100.
/// A chore never contributes more than its full weight, even if approved
/// more times than expected (parent restarts, duplicate approvals, etc.).
double kidProgressPct({
  required List<({double weightPct, String cadence, int approvedCount})> chores,
  required int weeksN,
}) {
  var total = 0.0;
  for (final c in chores) {
    final expected = expectedInstances(cadence: c.cadence, weeksN: weeksN);
    final done = c.approvedCount.clamp(0, expected);
    total +=
        instanceCreditPct(weightPct: c.weightPct, expectedInstances: expected) *
            done;
  }
  return total > 100 ? 100 : total;
}

/// Behind pace: linear projection of [progressPct] to the target date falls
/// short of 100%. Equivalent to progressPct < 100 * weeksElapsed / weeksN.
///
/// [planWeightSum] does not change the threshold (the bar needs 100 regardless
/// of oversubscription; slack is consumed before a kid is "behind"), but the
/// parent UI passes it for the oversubscribe-headroom card.
bool isBehindPace({
  required double progressPct,
  required int weeksN,
  required int weeksElapsed,
  required double planWeightSum,
}) {
  final n = weeksN < 1 ? 1 : weeksN;
  final elapsed = weeksElapsed.clamp(0, n);
  final expectedPace = 100.0 * elapsed / n;
  return progressPct + 1e-6 < expectedPace;
}

/// Parent money pace: what must be saved per remaining week to still hit
/// [target] by the deadline. Falls to zero once fully saved; oversaving
/// clamps at zero. This is the honest catch-up rate - the plan's weekly
/// figure never changes, this one does.
double requiredWeeklySave({
  required double target,
  required double saved,
  required int weeksN,
}) {
  final n = weeksN < 1 ? 1 : weeksN;
  final remaining = target - saved;
  if (remaining <= 0) return 0;
  return remaining / n;
}

/// Discrete random weight for kid-proposed bonus chores (stretch S3 helper).
/// Landing in a visible band keeps kids from lobbying for a fat percent.
double randomBonusWeightPct(Random rng) {
  const slots = [3.0, 5.0, 8.0, 10.0, 12.0];
  return slots[rng.nextInt(slots.length)];
}
