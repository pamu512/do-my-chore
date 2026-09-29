import 'chore_progress_math.dart';

enum KidRowKind { open, nextTry, sent }

const kKidBannedFragments = [
  'behind',
  'missed',
  'failed',
  'overdue',
  'rejected',
  'try again',
];

bool kidCopyAllowed(String s) {
  final lower = s.toLowerCase();
  return kKidBannedFragments.every((w) => !lower.contains(w));
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// ISO week-year + week number (Monday-start, Thursday determines the year).
(int, int) _isoWeek(DateTime d) {
  final date = DateTime.utc(d.year, d.month, d.day);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final weekYear = thursday.year;
  final jan4 = DateTime.utc(weekYear, 1, 4);
  final week1Thursday = jan4.add(Duration(days: 4 - jan4.weekday));
  final week = 1 + thursday.difference(week1Thursday).inDays ~/ 7;
  return (weekYear, week);
}

KidRowKind kidRowKind({
  required String? latestStatus,
  required DateTime? latestAt,
  required String cadence,
  required DateTime now,
}) {
  if (latestStatus == 'rejected') return KidRowKind.nextTry;
  if (latestStatus == 'pending') return KidRowKind.sent;
  if (latestStatus == 'approved' && latestAt != null) {
    if (cadence == 'once') return KidRowKind.sent;
    if (cadence == 'daily') {
      return _sameCalendarDay(latestAt, now) ? KidRowKind.sent : KidRowKind.open;
    }
    if (cadence == 'weekly') {
      return _isoWeek(latestAt) == _isoWeek(now)
          ? KidRowKind.sent
          : KidRowKind.open;
    }
  }
  return KidRowKind.open;
}

bool allSent(Iterable<KidRowKind> kinds) {
  final list = kinds.toList();
  if (list.isEmpty) return false;
  return list.every((k) => k == KidRowKind.sent);
}

double todayMovedPct({
  required List<({double weightPct, String cadence, DateTime? latestAt})>
      chores,
  required int weeksN,
  required DateTime now,
}) {
  var total = 0.0;
  for (final c in chores) {
    final at = c.latestAt;
    if (at == null || !_sameCalendarDay(at, now)) continue;
    final expected = expectedInstances(cadence: c.cadence, weeksN: weeksN);
    total += instanceCreditPct(
        weightPct: c.weightPct, expectedInstances: expected);
  }
  return total;
}

int checkInsToOnPace({
  required double progressPct,
  required int weeksN,
  required int weeksElapsed,
  required List<double> openCreditsDesc,
}) {
  if (!isBehindPace(
    progressPct: progressPct,
    weeksN: weeksN,
    weeksElapsed: weeksElapsed,
    planWeightSum: 100,
  )) {
    return 0;
  }
  final n = weeksN < 1 ? 1 : weeksN;
  final elapsed = weeksElapsed.clamp(0, n);
  final gap = 100.0 * elapsed / n - progressPct;
  var acc = 0.0;
  var count = 0;
  for (final credit in openCreditsDesc) {
    if (acc + 1e-6 >= gap) break;
    acc += credit;
    count += 1;
  }
  return count;
}

String kidHeroLine({required bool behindPace, required String goalMode}) {
  if (!behindPace) return 'Every check-in moves the bar.';
  final noun = goalMode == 'family_trip' ? 'trip' : 'reward';
  return 'Every check-in moves it. The $noun stays put.';
}

/// Parent Home rail only. Path/progress, not a carrot. Kid rail stays "100%".
String parentRailRightCap() => 'path to 100%';

const _ones = {
  1: 'One',
  2: 'Two',
  3: 'Three',
  4: 'Four',
  5: 'Five',
  6: 'Six',
  7: 'Seven',
  8: 'Eight',
  9: 'Nine',
  10: 'Ten',
};

String paceCardTitle(int checkIns) {
  if (checkIns <= 0) return 'Each check-in today moves the bar.';
  final word = _ones[checkIns] ?? '$checkIns';
  final noun = checkIns == 1 ? 'check-in' : 'check-ins';
  return '$word $noun today puts the week back on pace.';
}

String _shortChoreName(String title) {
  final t = title.trim().toLowerCase();
  const prefixes = [
    'make your ',
    'wash the ',
    'fold the ',
    'plan the ',
  ];
  for (final p in prefixes) {
    if (t.startsWith(p)) {
      final rest = t.substring(p.length);
      return rest.split(RegExp(r'\s+')).first;
    }
  }
  return t.split(RegExp(r'\s+')).last;
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String paceCardBody(List<String> openTitles) {
  if (openTitles.isEmpty) return 'Each check-in moves the bar.';
  final names = openTitles.map(_shortChoreName).toList();
  if (names.length == 1) {
    return '${_cap(names[0])} is right there - it moves the bar.';
  }
  if (names.length == 2) {
    return '${_cap(names[0])} and ${names[1]} are right there - each one moves the bar.';
  }
  return '${_cap(names[0])}, ${names[1]}, and more are right there - each one moves the bar.';
}

String earnedHandOff({required String goalMode}) {
  if (goalMode == 'family_trip') {
    return 'Every habit, all the way here. Your parent takes it from here - talk about the trip together tonight.';
  }
  return 'Every habit, all the way here. Your parent takes it from here - talk about it together tonight.';
}
