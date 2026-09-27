import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_auth.dart';
import '../models/role.dart';
import 'ai_service.dart';

/// Pure validation: a chore may demand photo proof only if a parent can
/// verify it by looking; weights must be positive and the plan must cover
/// at least 100% (oversubscribing is allowed and deliberate).
String? validatePlan(AiPlanSuggestion plan) {
  if (plan.chores.length < 4 || plan.chores.length > 8) {
    return 'Plan needs 4-8 chores';
  }
  if (plan.weeklyParentSave < 0) return 'Weekly save cannot be negative';
  if (plan.why.trim().isEmpty) return 'Plan must explain why';
  var weightSum = 0.0;
  for (final c in plan.chores) {
    if (c.weightPct <= 0) return 'Chore "${c.title}" needs a positive weight';
    if (!const ['once', 'daily', 'weekly'].contains(c.cadence)) {
      return 'Chore "${c.title}" has an unknown cadence';
    }
    if (c.isMakeup) {
      return 'Makeup chores are added later by the parent, never in the plan';
    }
    if (c.requiresPhoto && !kVisuallyVerifiable.contains(c.title)) {
      return 'Chore "${c.title}" cannot require a photo - it is not visually verifiable';
    }
    weightSum += c.weightPct;
  }
  if (weightSum + 1e-9 < 100) {
    return 'Weights must sum to at least 100% (now ${weightSum.toStringAsFixed(0)}%)';
  }
  return null;
}

/// Creates goals, stores suggestions, and (on accept) writes the chore rows.
/// All calls run under the caller's client — parent JWT by RLS contract.
class GoalService {
  GoalService(this._clients);

  final RoleClients _clients;

  SupabaseClient get _parent => _clients.forRole(Role.parent);

  /// Read access for query extensions in `queries.dart`.
  SupabaseClient get parentClient => _parent;

  /// Kid-JWT client for query extensions in `queries.dart`.
  SupabaseClient get kidClient => _clients.forRole(Role.kid);

  /// Returns the new goal id.
  Future<String> createGoal({
    required String title,
    required double cost,
    required String goalMode, // family_trip | kid_item
    DateTime? targetDate,
    bool allowMakeup = false,
  }) async {
    final row = await _parent.from('goals').insert({
      'title': title,
      'target_amount': cost,
      'goal_mode': goalMode,
      if (targetDate != null) 'target_date': targetDate.toIso8601String().substring(0, 10),
      'allow_makeup': allowMakeup,
    }).select('id').single();
    return row['id'] as String;
  }

  /// Stores the suggestion and writes chores for an accepted plan.
  /// Throws [ArgumentError] on invalid plans (weights under 100%, photo on a
  /// trust chore, makeup inside the initial plan, ...).
  Future<void> acceptPlan({
    required String goalId,
    required AiPlanSuggestion plan,
    String source = 'deterministic',
  }) async {
    final problem = validatePlan(plan);
    if (problem != null) throw ArgumentError(problem);

    await _parent.from('ai_plans').insert({
      'goal_id': goalId,
      'suggestion': plan.toJson(),
      'accepted': true,
      'source': source,
    });

    await _parent.from('chores').insert(
          plan.chores
              .map((c) => {
                    'goal_id': goalId,
                    'title': c.title,
                    'cadence': c.cadence,
                    'weight_pct': c.weightPct,
                    'requires_photo': c.requiresPhoto,
                  })
              .toList(),
        );
  }

  /// Parent logs money set aside for the goal ("I saved this week").
  /// In-app planner only; the parent settles real money offline.
  Future<void> logParentSave({
    required String goalId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('Save amount must be positive');
    await _parent.from('parent_save_entries').insert({
      'goal_id': goalId,
      'amount': amount,
      'note': ?note,
    });
  }

  /// Parent adds a one-time makeup chore while the goal allows makeup. Never
  /// automatic: the parent opts in on the goal and adds it explicitly.
  Future<void> addMakeupChore({
    required String goalId,
    required String title,
    required double weightPct,
    bool requiresPhoto = false,
  }) async {
    if (weightPct <= 0 || weightPct > 100) {
      throw ArgumentError('Makeup weight must be between 0 and 100');
    }
    final goal = await _parent
        .from('goals')
        .select('allow_makeup')
        .eq('id', goalId)
        .single();
    if (goal['allow_makeup'] != true) {
      throw StateError('Makeup chores are disabled for this goal');
    }
    await _parent.from('chores').insert({
      'goal_id': goalId,
      'title': title,
      'cadence': 'once',
      'weight_pct': weightPct,
      'requires_photo': requiresPhoto,
      'is_makeup': true,
    });
  }
}
