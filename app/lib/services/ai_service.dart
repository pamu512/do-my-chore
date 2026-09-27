/// AI Suggest Plan service.
///
/// The edge function (`supabase/functions/suggest-plan`) is the live path;
/// this module holds the shared shape plus the deterministic fallback that
/// must behave identically with zero API keys — the hackathon demo always
/// runs on this path.
library;

/// Chore titles that can legitimately require photo proof — things a parent
/// can verify by looking. Anything time- or trust-based must never demand a
/// photo ("read a chapter" is an honor-system chore).
const Set<String> kVisuallyVerifiable = {
  'Clean the play table',
  'Wash the dishes',
  'Vacuum the living room',
  'Tidy your room',
  'Set and clear the table',
  'Take out the recycling',
};

class ChoreSpec {
  final String title;
  final double reward;
  final bool requiresPhoto;
  final int splitGoalPct; // % of reward that goes to the goal bank

  const ChoreSpec({
    required this.title,
    required this.reward,
    required this.requiresPhoto,
    required this.splitGoalPct,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'reward': reward,
        'requires_photo': requiresPhoto,
        'split_goal_pct': splitGoalPct,
      };

  static ChoreSpec fromJson(Map<String, dynamic> j) => ChoreSpec(
        title: j['title'] as String,
        reward: (j['reward'] as num).toDouble(),
        requiresPhoto: j['requires_photo'] == true,
        splitGoalPct: (j['split_goal_pct'] as num).toInt(),
      );
}

class AiPlanSuggestion {
  final double weeklyTopup;
  final List<ChoreSpec> chores;
  final String why;

  const AiPlanSuggestion({
    required this.weeklyTopup,
    required this.chores,
    required this.why,
  });

  Map<String, dynamic> toJson() => {
        'weekly_topup': weeklyTopup,
        'chores': chores.map((c) => c.toJson()).toList(),
        'why': why,
      };

  static AiPlanSuggestion fromJson(Map<String, dynamic> j) =>
      AiPlanSuggestion(
        weeklyTopup: (j['weekly_topup'] as num).toDouble(),
        chores: (j['chores'] as List)
            .map((c) => ChoreSpec.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        why: j['why'] as String,
      );
}

/// Whole weeks from today until [target]; at least 1.
int weeksUntil(DateTime target) {
  final days = target.difference(DateTime.now()).inDays;
  return (days / 7).ceil().clamp(1, 520);
}

double _round25(double v) => (v * 4).roundToDouble() / 4;

const List<ChoreSpec> _kidChores = [
  ChoreSpec(title: 'Clean the play table', reward: 5, requiresPhoto: true, splitGoalPct: 80),
  ChoreSpec(title: 'Read for 20 minutes', reward: 3, requiresPhoto: false, splitGoalPct: 100),
  ChoreSpec(title: 'Wash the dishes', reward: 4, requiresPhoto: true, splitGoalPct: 80),
  ChoreSpec(title: 'Make your bed', reward: 2, requiresPhoto: false, splitGoalPct: 100),
  ChoreSpec(title: 'Vacuum the living room', reward: 5, requiresPhoto: true, splitGoalPct: 60),
  ChoreSpec(title: 'Take out the recycling', reward: 3, requiresPhoto: false, splitGoalPct: 100),
];

const List<ChoreSpec> _littleKidChores = [
  ChoreSpec(title: 'Tidy your room', reward: 4, requiresPhoto: true, splitGoalPct: 80),
  ChoreSpec(title: 'Set and clear the table', reward: 3, requiresPhoto: true, splitGoalPct: 80),
  ChoreSpec(title: 'Read for 20 minutes', reward: 3, requiresPhoto: false, splitGoalPct: 100),
  ChoreSpec(title: 'Make your bed', reward: 2, requiresPhoto: false, splitGoalPct: 100),
  ChoreSpec(title: 'Take out the recycling', reward: 3, requiresPhoto: false, splitGoalPct: 100),
];

/// Deterministic save plan: parent tops up 30% weekly, chores cover the rest.
/// No API key, no randomness — same inputs always give the same plan.
AiPlanSuggestion buildDeterministicPlan({
  required String title,
  required double targetAmount,
  required int weeks,
  required int kidAge,
}) {
  final w = weeks < 1 ? 1 : weeks;
  final weeklyTotal = targetAmount / w;
  final weeklyTopup = _round25(weeklyTotal * 0.30);
  final choreWeeklyNeeded = weeklyTotal - weeklyTopup;

  final catalog = kidAge <= 7 ? _littleKidChores : _kidChores;
  final baseSum = catalog.fold<double>(0, (s, c) => s + c.reward);
  final scale = baseSum > 0 ? choreWeeklyNeeded / baseSum : 1.0;

  final chores = catalog
      .map((c) => ChoreSpec(
            title: c.title,
            reward: _round25(c.reward * scale).clamp(0.50, 50.0),
            requiresPhoto: c.requiresPhoto && kVisuallyVerifiable.contains(c.title),
            splitGoalPct: c.splitGoalPct,
          ))
      .toList();

  final choreWeekly = chores.fold<double>(0, (s, c) => s + c.reward);
  final why = 'Over $w weeks, "$title" needs \$$targetAmount. '
      'Putting in \$${weeklyTopup.toStringAsFixed(0)} a week from your own money, plus about '
      '\$${choreWeekly.toStringAsFixed(0)} a week that ${kidAge <= 7 ? 'your little one' : 'your kid'} earns from these chores, '
      'gets there right on time — no end-of-plan scramble. Chores with a camera icon just need a quick photo so you can see the result yourself.';

  return AiPlanSuggestion(weeklyTopup: weeklyTopup, chores: chores, why: why);
}
