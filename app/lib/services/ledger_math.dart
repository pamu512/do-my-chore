/// Parent-side save planning math (rev 3).
///
/// The kid earns the goal in percent (see `chore_progress_math.dart`);
/// dollars exist only on parent screens: the cost of the goal and the save
/// cadence needed to fund it by the target date. Money is settled offline;
/// nothing here connects to a bank.
library;

/// Amount to set aside per week to fund [cost] over [weeksN].
double suggestedSavePerWeek({required double cost, required int weeksN}) {
  final n = weeksN < 1 ? 1 : weeksN;
  return cost / n;
}

/// Amount to set aside per day (week / 7).
double suggestedSavePerDay({required double cost, required int weeksN}) =>
    suggestedSavePerWeek(cost: cost, weeksN: weeksN) / 7;

/// Amount to set aside per month (calendar-ish months ceil(weeksN / 4.345)).
double suggestedSavePerMonth({required double cost, required int weeksN}) {
  final n = weeksN < 1 ? 1 : weeksN;
  final months = (n / 4.345).ceil();
  return cost / months;
}

/// Fraction of the cost already logged as saved, capped at 1.
double parentSaveProgress({required double saved, required double cost}) {
  if (cost <= 0) return 0;
  final p = saved / cost;
  return p > 1 ? 1 : p;
}
