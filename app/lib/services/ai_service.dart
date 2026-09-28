/// AI Suggest Plan service (rev 3).
///
/// The plan is habit-first: chores with cadence + weight (summing to at least
/// 100%) for the kid, and a parent-only weekly save for the real cost. The
/// edge function (`supabase/functions/suggest-plan`) is the live path; this
/// module holds the shared shape plus the deterministic fallback that must
/// behave identically with zero API keys.
library;

import 'chore_progress_math.dart';

/// Chore titles that can legitimately require photo proof — things a parent
/// can verify by looking. Anything time- or trust-based must never demand a
/// photo ("read a chapter" is an honor-system chore).
const Set<String> kVisuallyVerifiable = {
  'Make your bed',
  'Wash the dishes',
  'Fold the laundry',
  'Clean the play table',
  'Vacuum the living room',
  'Tidy your room',
  'Set and clear the table',
  'Take out the recycling',
};

class ChoreSpec {
  final String title;
  final String cadence; // once | daily | weekly
  final double weightPct;
  final bool requiresPhoto;
  final bool isMakeup;

  const ChoreSpec({
    required this.title,
    required this.cadence,
    required this.weightPct,
    required this.requiresPhoto,
    this.isMakeup = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'cadence': cadence,
        'weight_pct': weightPct,
        'requires_photo': requiresPhoto,
        'is_makeup': isMakeup,
      };

  static ChoreSpec fromJson(Map<String, dynamic> j) => ChoreSpec(
        title: j['title'] as String,
        cadence: j['cadence'] as String,
        weightPct: (j['weight_pct'] as num).toDouble(),
        requiresPhoto: j['requires_photo'] == true,
        isMakeup: j['is_makeup'] == true,
      );
}

class AiPlanSuggestion {
  final double weeklyParentSave;
  final List<ChoreSpec> chores;
  final String why;

  const AiPlanSuggestion({
    required this.weeklyParentSave,
    required this.chores,
    required this.why,
  });

  double get weightSum => chores.fold(0, (s, c) => s + c.weightPct);

  Map<String, dynamic> toJson() => {
        'weekly_parent_save': weeklyParentSave,
        'chores': chores.map((c) => c.toJson()).toList(),
        'why': why,
      };

  static AiPlanSuggestion fromJson(Map<String, dynamic> j) => AiPlanSuggestion(
        weeklyParentSave: (j['weekly_parent_save'] as num).toDouble(),
        chores: (j['chores'] as List)
            .map((c) => ChoreSpec.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        why: j['why'] as String,
      );
}

/// Whole weeks from today until [target]; at least 1.
int weeksUntil(DateTime target) =>
    weeksRemaining(today: DateTime.now(), targetDate: target);

double _round25(double v) => (v * 4).roundToDouble() / 4;

const List<ChoreSpec> _kidChores = [
  ChoreSpec(title: 'Make your bed', cadence: 'daily', weightPct: 40, requiresPhoto: true),
  ChoreSpec(title: 'Wash the dishes', cadence: 'daily', weightPct: 30, requiresPhoto: true),
  ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true),
  ChoreSpec(title: 'Plan the park itinerary', cadence: 'once', weightPct: 10, requiresPhoto: false),
];

const List<ChoreSpec> _littleKidChores = [
  ChoreSpec(title: 'Tidy your room', cadence: 'daily', weightPct: 40, requiresPhoto: true),
  ChoreSpec(title: 'Set and clear the table', cadence: 'daily', weightPct: 30, requiresPhoto: true),
  ChoreSpec(title: 'Fold the laundry', cadence: 'weekly', weightPct: 20, requiresPhoto: true),
  ChoreSpec(title: 'Plan the week together', cadence: 'once', weightPct: 10, requiresPhoto: false),
];

/// Deterministic habit plan: worked-example weights summing to exactly 100,
/// plus the parent's weekly save for the real cost. No API key, no randomness
/// — same inputs always give the same plan.
AiPlanSuggestion buildDeterministicPlan({
  required String title,
  required double targetAmount,
  required int weeks,
  required int kidAge,
}) {
  final w = weeks < 1 ? 1 : weeks;
  final weeklySave = _round25(targetAmount / w);

  final catalog = kidAge <= 7 ? _littleKidChores : _kidChores;
  final weightSum = catalog.fold<double>(0, (s, c) => s + c.weightPct);
  final who = kidAge <= 7 ? 'your little one' : 'your kid';

  final why = '"$title" costs about \$$targetAmount. Setting aside '
      '\$$weeklySave a week for $w weeks covers the full cost before the date. '
      'Meanwhile $who earns the goal by keeping the habits going: the weight '
      'list adds up to $weightSum percent, so a steady streak lands exactly '
      'at 100 percent by the deadline.';

  return AiPlanSuggestion(
    weeklyParentSave: weeklySave,
    chores: catalog.toList(),
    why: why,
  );
}
