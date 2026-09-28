/// Thin clients for optional edge functions. Every method falls back so
/// Basics / offline still works with zero keys and no function deploy.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

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
    );
    final data = res.data;
    if (data is Map) {
      return PhotoAssistResult.fromJson(Map<String, dynamic>.from(data));
    }
  } catch (_) {
    // ponytail: function missing / no key / network → abstain
  }
  return const PhotoAssistResult(
    suggest: 'abstain',
    reason: 'Photo check is not configured — your call, parent.',
  );
}

/// Invokes `goal-cost-orchestrate`. On any failure, local deterministic bands.
Future<CostOrchestrateResult> invokeGoalCostOrchestrate(
  SupabaseClient client, {
  required String title,
  required double targetAmount,
  DateTime? targetDate,
  String goalMode = 'kid_item',
}) async {
  final weeks = targetDate == null ? 12 : weeksUntil(targetDate);
  try {
    final res = await client.functions.invoke(
      'goal-cost-orchestrate',
      body: {
        'title': title,
        'targetAmount': targetAmount,
        'targetDate': targetDate?.toIso8601String().substring(0, 10),
        'goalMode': goalMode,
      },
    );
    final data = res.data;
    if (data is Map) {
      return parseCostOrchestrateResponse(
        Map<String, dynamic>.from(data),
        fallbackTitle: title,
        fallbackCost: targetAmount,
        fallbackWeeks: weeks,
      );
    }
  } catch (_) {
    // ponytail: function missing / no key / network → local bands
  }
  final estimate = buildDeterministicCostEstimate(
    title: title,
    enteredCost: targetAmount,
    weeks: weeks,
  );
  return CostOrchestrateResult(
    estimate: estimate,
    weeklySaveSuggestion: estimate.weeklySaveSuggestion,
    deals: const [],
    dealSearch: 'skipped',
  );
}

extension GoalServiceAi on GoalService {
  /// Live suggest-plan when the function is deployed; otherwise the local
  /// deterministic builder (the Flutter path used today).
  Future<AiPlanSuggestion> suggestPlan({
    required String title,
    required double targetAmount,
    required DateTime targetDate,
    required int kidAge,
  }) async {
    try {
      final res = await parentClient.functions.invoke(
        'suggest-plan',
        body: {
          'title': title,
          'targetAmount': targetAmount,
          'targetDate': targetDate.toIso8601String().substring(0, 10),
          'kidAge': kidAge,
        },
      );
      final data = res.data;
      if (data is Map) {
        final plan = AiPlanSuggestion.fromJson(Map<String, dynamic>.from(data));
        if (validatePlan(plan) == null) return plan;
      }
    } catch (_) {
      // ponytail: keep the offline builder as the source of truth
    }
    return buildDeterministicPlan(
      title: title,
      targetAmount: targetAmount,
      weeks: weeksUntil(targetDate),
      kidAge: kidAge,
    );
  }
}
