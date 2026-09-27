import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_auth.dart';
import '../models/role.dart';
import 'ai_service.dart';

/// Pure validation: a chore may demand photo proof only if a parent can
/// verify it by looking. Used client-side on accept AND mirrored in the
/// accept path so a bad suggestion never lands in the DB.
String? validatePlan(AiPlanSuggestion plan) {
  if (plan.chores.length < 4 || plan.chores.length > 8) {
    return 'Plan needs 4-8 chores';
  }
  if (plan.weeklyTopup < 0) return 'Weekly top-up cannot be negative';
  if (plan.why.trim().isEmpty) return 'Plan must explain why';
  for (final c in plan.chores) {
    if (c.reward <= 0) return 'Chore "${c.title}" needs a positive reward';
    if (c.requiresPhoto && !kVisuallyVerifiable.contains(c.title)) {
      return 'Chore "${c.title}" cannot require a photo — it is not visually verifiable';
    }
  }
  return null;
}

/// Creates a goal, stores the suggestion, and (on accept) writes the chore
/// rows. All calls run under the caller's client — parent JWT by RLS contract.
class GoalService {
  GoalService(this._clients);

  final RoleClients _clients;

  SupabaseClient get _parent => _clients.forRole(Role.parent);

  /// Read access for query extensions in `queries.dart`.
  SupabaseClient get parentClient => _parent;

  /// Returns the new goal id.
  Future<String> createGoal({
    required String title,
    required double targetAmount,
    DateTime? targetDate,
  }) async {
    final row = await _parent.from('goals').insert({
      'title': title,
      'target_amount': targetAmount,
      if (targetDate != null) 'target_date': targetDate.toIso8601String().substring(0, 10),
    }).select('id').single();
    return row['id'] as String;
  }

  /// Stores the suggestion and writes chores for an accepted plan.
  /// Throws [ArgumentError] on invalid plans (e.g. photo on a trust chore).
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
                    'reward_amount': c.reward,
                    'default_split_goal_pct': c.splitGoalPct,
                    'requires_photo': c.requiresPhoto,
                  })
              .toList(),
        );
  }
}
