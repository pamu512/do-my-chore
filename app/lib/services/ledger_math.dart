/// Pure ledger math for Do My Chore.
///
/// Money rule (design rev 2): `ledger_entries` is the source of truth and
/// balances are computed on read. Overshoot fills the goal to its target and
/// the remainder overflows to pocket. All arithmetic runs in integer cents to
/// keep the split exact.
library;

enum LedgerKind { goalCredit, pocketCredit, parentTopup }

class LedgerEntry {
  final LedgerKind kind;
  final double amount;
  final String? goalId;

  const LedgerEntry({required this.kind, required this.amount, this.goalId});
}

class BalanceSummary {
  final double goalBank;
  final double pocket;

  const BalanceSummary({required this.goalBank, required this.pocket});
}

int _cents(double v) => (v * 100).round();

double _money(int c) => c / 100.0;

/// Sums ledger entries into a goal bank (goal credits + parent top-ups) and
/// pocket total. Balances are always derived, never stored.
BalanceSummary sumLedger(List<LedgerEntry> entries) {
  var goalC = 0;
  var pocketC = 0;
  for (final e in entries) {
    if (e.kind == LedgerKind.pocketCredit) {
      pocketC += _cents(e.amount);
    } else {
      goalC += _cents(e.amount);
    }
  }
  return BalanceSummary(goalBank: _money(goalC), pocket: _money(pocketC));
}

/// Splits a credit between the goal bank (up to its target) and pocket.
/// The goal never overshoots: it receives at most the remaining room, and the
/// remainder goes to pocket — both parts are written in the same transaction
/// by the caller.
({double goalCredit, double pocketCredit}) splitCredit({
  required double amount,
  required double goalBalance,
  required double targetAmount,
}) {
  final amountC = _cents(amount);
  final roomC = (_cents(targetAmount) - _cents(goalBalance)).clamp(0, amountC);
  return (goalCredit: _money(roomC), pocketCredit: _money(amountC - roomC));
}

/// Progress fraction for the UI bar, capped at 1.0; zero target -> 0.
double goalProgress({required double goalBank, required double targetAmount}) {
  if (targetAmount <= 0) return 0.0;
  final pct = _cents(goalBank) / _cents(targetAmount);
  return pct > 1.0 ? 1.0 : pct;
}

/// Whole weeks until the goal is funded at [weeklyTopup] per week.
/// Returns null when there is no top-up (caller shows "top up now" instead).
int? weeksToGoal({
  required double goalBank,
  required double targetAmount,
  required double weeklyTopup,
}) {
  final topupC = _cents(weeklyTopup);
  if (topupC <= 0) return null;
  final remainingC = _cents(targetAmount) - _cents(goalBank);
  if (remainingC <= 0) return 0;
  return (remainingC + topupC - 1) ~/ topupC;
}
