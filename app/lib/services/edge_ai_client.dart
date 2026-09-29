/// Thin clients for optional edge functions. Every method falls back so
/// Basics / offline still works with zero keys and no function deploy.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/family_context.dart';
import 'ai_service.dart';
import 'cost_estimate.dart';
import 'goal_service.dart';

class PhotoAssistResult {
  final String suggest; // approve | reject | abstain
  final String reason;

  const PhotoAssistResult({required this.suggest, required this.reason});

  static PhotoAssistResult fromJson(Map<String, dynamic> j) => PhotoAssistResult(
        suggest: (j['suggest'] as String?) ?? 'abstain',
        reason: (j['reason'] as String?) ?? 'Photo check is not configured.',
      );
}

/// Invokes `photo-assist`. On any failure, abstains — parent stays final.
Future<PhotoAssistResult> invokePhotoAssist(
  SupabaseClient client, {
  required String choreTitle,
  String? imageBase64,
}) async {
  try {
    final res = await client.functions.invoke(
      'photo-assist',
      body: {'choreTitle': choreTitle, 'image': imageBase64},
    ).timeout(const Duration(seconds: 8));
    final data = res.data;
    if (data is Map) {
      return PhotoAssistResult.fromJson(Map<String, dynamic>.from(data));
    }
  } catch (_) {
    // ponytail: function missing / no key / network → abstain
  }
  return const PhotoAssistResult(
    suggest: 'abstain',
    reason: 'Photo check is not configured - your call, parent.',
  );
}

/// Invokes `goal-cost-orchestrate`. Amount optional. On any failure, local bands.
Future<CostOrchestrateResult> invokeGoalCostOrchestrate(
  SupabaseClient client, {
  required String title,
  double? targetAmount,
  DateTime? targetDate,
  String goalMode = 'kid_item',
  int kidAge = kPrimaryKidAge,
}) async {
  final weeks = targetDate == null ? 12 : weeksUntil(targetDate);
  try {
    final res = await client.functions.invoke(
      'goal-cost-orchestrate',
      body: {
        'goalText': title,
        'title': title,
        if (targetAmount != null && targetAmount > 0) 'targetAmount': targetAmount,
        'targetDate': targetDate?.toIso8601String().substring(0, 10),
        'goalMode': goalMode,
        'kidAge': kidAge,
      },
    ).timeout(const Duration(seconds: 12));
    final data = res.data;
    if (data is Map) {
      return parseCostOrchestrateResponse(
        Map<String, dynamic>.from(data),
        fallbackTitle: title,
        fallbackCost: targetAmount,
        fallbackWeeks: weeks,
        fallbackGoalMode: goalMode,
      );
    }
  } catch (_) {
    // ponytail: function missing / no key / network → local bands
  }
  final estimate = localCostEstimate(
    title: title,
    enteredCost: targetAmount,
    weeks: weeks,
    goalMode: goalMode,
  );
  return CostOrchestrateResult(
    estimate: estimate,
    weeklySaveSuggestion: estimate.weeklySaveSuggestion,
    deals: const [],
    dealSearch: 'skipped',
  );
}

class SuggestPlanResult {
  final AiPlanSuggestion plan;
  final String source; // llm | deterministic
  final CostEstimate estimate;
  final List<GoalDeal> deals;
  final String dealSearch;
  final int weeks;

  const SuggestPlanResult({
    required this.plan,
    required this.source,
    required this.estimate,
    this.deals = const [],
    this.dealSearch = 'skipped',
    this.weeks = 12,
  });
}

/// Local-only goal-first result (zero-key / DEMO_WALK / catch).
SuggestPlanResult localGoalFirstSuggest({
  required String title,
  double? targetAmount,
  required int weeks,
  required int kidAge,
  String goalMode = 'kid_item',
}) {
  final estimate = localCostEstimate(
    title: title,
    enteredCost: targetAmount,
    weeks: weeks,
    goalMode: goalMode,
  );
  final amount = (targetAmount != null && targetAmount > 0)
      ? targetAmount
      : estimate.likely;
  return SuggestPlanResult(
    plan: buildDeterministicPlan(
      title: title,
      targetAmount: amount,
      weeks: weeks,
      kidAge: kidAge,
    ),
    source: 'deterministic',
    estimate: estimate,
    deals: const [],
    dealSearch: 'skipped',
    weeks: weeks,
  );
}

/// Parse the combined suggest-plan payload. Bad/partial JSON → local fallback.
SuggestPlanResult parseSuggestPlanPayload(
  Map<String, dynamic> raw, {
  required String fallbackTitle,
  double? fallbackCost,
  required int fallbackWeeks,
  required int kidAge,
  String goalMode = 'kid_item',
}) {
  final local = localGoalFirstSuggest(
    title: fallbackTitle,
    targetAmount: fallbackCost,
    weeks: fallbackWeeks,
    kidAge: kidAge,
    goalMode: goalMode,
  );
  try {
    final plan = AiPlanSuggestion.fromJson(raw);
    if (validatePlan(plan) != null) return local;
    final estimateRaw = raw['estimate'];
    final estimate = estimateRaw is Map
        ? CostEstimate.fromJson(
            Map<String, dynamic>.from(estimateRaw),
            weeklySaveSuggestion: (raw['weekly_save_suggestion'] as num?)
                    ?.toDouble() ??
                local.estimate.weeklySaveSuggestion,
          )
        : local.estimate;
    final deals = ((raw['deals'] as List?) ?? const [])
        .whereType<Map>()
        .map((d) => GoalDeal.fromJson(Map<String, dynamic>.from(d)))
        .toList();
    final weeks = (raw['weeks'] as num?)?.toInt() ?? fallbackWeeks;
    final source = estimate.provider == 'deterministic' ? 'deterministic' : 'llm';
    return SuggestPlanResult(
      plan: plan,
      source: source,
      estimate: estimate,
      deals: deals,
      dealSearch: (raw['deal_search'] as String?) ?? 'skipped',
      weeks: weeks,
    );
  } catch (_) {
    return local;
  }
}

/// DEMO_WALK and missing payloads stay local. Used by tests and the client.
SuggestPlanResult resolveSuggestPlan({
  required bool demoWalk,
  Map<String, dynamic>? edgePayload,
  required String title,
  double? targetAmount,
  required int weeks,
  required int kidAge,
  String goalMode = 'kid_item',
}) {
  if (demoWalk) {
    return localGoalFirstSuggest(
      title: title,
      targetAmount: targetAmount,
      weeks: weeks,
      kidAge: kidAge,
      goalMode: goalMode,
    );
  }
  if (edgePayload != null) {
    return parseSuggestPlanPayload(
      edgePayload,
      fallbackTitle: title,
      fallbackCost: targetAmount,
      fallbackWeeks: weeks,
      kidAge: kidAge,
      goalMode: goalMode,
    );
  }
  return localGoalFirstSuggest(
    title: title,
    targetAmount: targetAmount,
    weeks: weeks,
    kidAge: kidAge,
    goalMode: goalMode,
  );
}

extension GoalServiceAi on GoalService {
  /// Live suggest-plan when the function is deployed; otherwise the local
  /// deterministic builder (the Flutter path used today).
  Future<SuggestPlanResult> suggestPlan({
    required String title,
    double? targetAmount,
    required DateTime targetDate,
    required int kidAge,
    String goalMode = 'kid_item',
  }) async {
    final weeks = weeksUntil(targetDate);
    SuggestPlanResult local() => localGoalFirstSuggest(
          title: title,
          targetAmount: targetAmount,
          weeks: weeks,
          kidAge: kidAge,
          goalMode: goalMode,
        );
    // Basics video / walkthrough: never block on a network plan.
    if (const bool.fromEnvironment('DEMO_WALK')) return local();
    try {
      final res = await parentClient.functions.invoke(
        'suggest-plan',
        body: {
          'goalText': title,
          'title': title,
          if (targetAmount != null && targetAmount > 0) 'targetAmount': targetAmount,
          'targetDate': targetDate.toIso8601String().substring(0, 10),
          'kidAge': kidAge,
          'goalMode': goalMode,
        },
      ).timeout(const Duration(seconds: 8));
      final data = res.data;
      if (data is Map) {
        return parseSuggestPlanPayload(
          Map<String, dynamic>.from(data),
          fallbackTitle: title,
          fallbackCost: targetAmount,
          fallbackWeeks: weeks,
          kidAge: kidAge,
          goalMode: goalMode,
        );
      }
    } catch (_) {
      // ponytail: keep the offline builder as the source of truth
    }
    return local();
  }
}
