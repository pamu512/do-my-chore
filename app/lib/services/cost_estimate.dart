/// Parent-side real-world cost bands (low / likely / high) used after Accept.
///
/// The edge function (`goal-cost-orchestrate`) is the live path when a key is
/// configured. This module is the offline / Basics fallback: same JSON shape,
/// no network, no API key. Kid chore progress stays percent-based elsewhere.
library;

import 'ledger_math.dart';

double _round25(double v) => (v * 4).roundToDouble() / 4;

/// First `$1,234.56` (or `$199`) in a snippet, or null.
double? extractUsdPrice(String text) {
  final match = RegExp(r'\$([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)')
      .firstMatch(text);
  if (match == null) return null;
  return double.tryParse(match.group(1)!.replaceAll(',', ''));
}

class GoalDeal {
  final String title;
  final String url;
  final double? price;
  final String? snippet;
  final String source;

  const GoalDeal({
    required this.title,
    required this.url,
    this.price,
    this.snippet,
    this.source = 'tavily',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (price != null) 'price': price,
        if (snippet != null) 'snippet': snippet,
        'source': source,
      };

  static GoalDeal fromJson(Map<String, dynamic> j) => GoalDeal(
        title: (j['title'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        price: (j['price'] as num?)?.toDouble(),
        snippet: j['snippet'] as String?,
        source: (j['source'] as String?) ?? 'tavily',
      );
}

class CostEstimate {
  final double low;
  final double likely;
  final double high;
  final String currency;
  final String rationale;
  final String provider; // nebius | openai | deterministic
  final double weeklySaveSuggestion;

  const CostEstimate({
    required this.low,
    required this.likely,
    required this.high,
    required this.rationale,
    required this.provider,
    required this.weeklySaveSuggestion,
    this.currency = 'USD',
  });

  Map<String, dynamic> toJson() => {
        'low': low,
        'likely': likely,
        'high': high,
        'currency': currency,
        'rationale': rationale,
        'provider': provider,
      };

  static CostEstimate fromJson(Map<String, dynamic> j, {required double weeklySaveSuggestion}) =>
      CostEstimate(
        low: (j['low'] as num).toDouble(),
        likely: (j['likely'] as num).toDouble(),
        high: (j['high'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'USD',
        rationale: (j['rationale'] as String?) ?? '',
        provider: (j['provider'] as String?) ?? 'deterministic',
        weeklySaveSuggestion: weeklySaveSuggestion,
      );
}

class CostOrchestrateResult {
  final CostEstimate estimate;
  final double weeklySaveSuggestion;
  final List<GoalDeal> deals;
  final String dealSearch; // tavily | skipped

  const CostOrchestrateResult({
    required this.estimate,
    required this.weeklySaveSuggestion,
    required this.deals,
    required this.dealSearch,
  });
}

class LockPayload {
  final double targetAmount;
  final double weeklyParentSave;
  final Map<String, dynamic> costEstimate;
  final Map<String, dynamic>? deal;

  const LockPayload({
    required this.targetAmount,
    required this.weeklyParentSave,
    required this.costEstimate,
    this.deal,
  });
}

/// Static USD priors when the parent has not entered an amount.
/// Matches `supabase/functions/_shared/goal_estimate.ts`. Not live prices.
const Map<String, ({double low, double likely, double high})> kCostPriors = {
  'family_trip': (low: 800, likely: 1200, high: 1800),
  'kid_item': (low: 40, likely: 80, high: 150),
  'other': (low: 80, likely: 150, high: 250),
};

/// Offline bands from a goal_mode prior when amount is unknown.
CostEstimate buildDeterministicCostPrior({
  required String title,
  required String goalMode,
  required int weeks,
}) {
  final w = weeks < 1 ? 1 : weeks;
  final prior = kCostPriors[goalMode] ?? kCostPriors['other']!;
  final weekly = suggestedSavePerWeek(cost: prior.likely, weeksN: w);
  return CostEstimate(
    low: prior.low,
    likely: prior.likely,
    high: prior.high,
    rationale:
        '"$title" has no amount yet. This offline band is a starting point for a ${goalMode.replaceAll('_', ' ')}, not a live price. Confirm or change the likely number before you lock it. About \$${weekly.toStringAsFixed(0)} a week for $w weeks covers the likely figure.',
    provider: 'deterministic',
    weeklySaveSuggestion: weekly,
  );
}

/// Offline bands around the number the parent already typed.
CostEstimate buildDeterministicCostEstimate({
  required String title,
  required double enteredCost,
  required int weeks,
}) {
  if (enteredCost <= 0) {
    throw ArgumentError('Entered cost must be positive');
  }
  final w = weeks < 1 ? 1 : weeks;
  final likely = enteredCost;
  final low = _round25(likely * 0.80);
  final high = _round25(likely * 1.25);
  final weekly = suggestedSavePerWeek(cost: likely, weeksN: w);
  return CostEstimate(
    low: low,
    likely: likely,
    high: high,
    rationale:
        '"$title" is entered at \$${likely.toStringAsFixed(0)}. Without live prices we treat that as the likely cost, with a lower band around 80% and a higher band around 125% so you can lock a number that still feels honest.',
    provider: 'deterministic',
    weeklySaveSuggestion: weekly,
  );
}

/// Prefer priced deals at or under [budget]. If nothing has a parseable
/// price, keep the first three links so the parent still has something to
/// look at. All-over-budget priced lists stay empty.
List<GoalDeal> dealsUnderBudget(List<GoalDeal> deals, {required double budget}) {
  final priced = deals
      .where((d) => d.price != null && d.price! <= budget + 1e-9)
      .toList();
  if (priced.isNotEmpty) return priced.take(3).toList();
  if (deals.any((d) => d.price != null)) return const [];
  return deals.take(3).toList();
}

CostEstimate localCostEstimate({
  required String title,
  double? enteredCost,
  required int weeks,
  String goalMode = 'kid_item',
}) {
  if (enteredCost != null && enteredCost > 0) {
    return buildDeterministicCostEstimate(
      title: title,
      enteredCost: enteredCost,
      weeks: weeks,
    );
  }
  return buildDeterministicCostPrior(
    title: title,
    goalMode: goalMode,
    weeks: weeks,
  );
}

CostOrchestrateResult parseCostOrchestrateResponse(
  Map<String, dynamic> raw, {
  String fallbackTitle = 'Goal',
  double? fallbackCost,
  int fallbackWeeks = 12,
  String fallbackGoalMode = 'kid_item',
}) {
  final estimateRaw = raw['estimate'];
  if (estimateRaw is! Map) {
    final fallback = localCostEstimate(
      title: fallbackTitle,
      enteredCost: fallbackCost,
      weeks: fallbackWeeks,
      goalMode: fallbackGoalMode,
    );
    return CostOrchestrateResult(
      estimate: fallback,
      weeklySaveSuggestion: fallback.weeklySaveSuggestion,
      deals: const [],
      dealSearch: 'skipped',
    );
  }
  final weekly = (raw['weekly_save_suggestion'] as num?)?.toDouble() ??
      suggestedSavePerWeek(
        cost: (estimateRaw['likely'] as num).toDouble(),
        weeksN: fallbackWeeks,
      );
  final deals = ((raw['deals'] as List?) ?? const [])
      .whereType<Map>()
      .map((d) => GoalDeal.fromJson(Map<String, dynamic>.from(d)))
      .toList();
  return CostOrchestrateResult(
    estimate: CostEstimate.fromJson(
      Map<String, dynamic>.from(estimateRaw),
      weeklySaveSuggestion: weekly,
    ),
    weeklySaveSuggestion: weekly,
    deals: deals,
    dealSearch: (raw['deal_search'] as String?) ?? 'skipped',
  );
}

LockPayload lockPayload({
  required CostEstimate estimate,
  required double lockedAmount,
  required int weeks,
  GoalDeal? deal,
}) {
  if (lockedAmount <= 0) {
    throw ArgumentError('Locked cost must be positive');
  }
  return LockPayload(
    targetAmount: lockedAmount,
    weeklyParentSave: suggestedSavePerWeek(cost: lockedAmount, weeksN: weeks),
    costEstimate: estimate.toJson(),
    deal: deal?.toJson(),
  );
}
