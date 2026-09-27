import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_auth.dart';
import '../models/role.dart';
import 'ledger_math.dart';

/// Allowed submission status transitions. A rejected row is never flipped
/// back to pending — a retry always inserts a new submission row.
const Map<String, List<String>> kAllowedTransitions = {
  'pending': ['approved', 'rejected'],
};

/// Credit split for an approved chore: reward is split by the chore's goal
/// percentage, then the goal share is capped at the target — overshoot flows
/// to pocket. Same rule as [splitCredit], applied to the reward split.
({double goalCredit, double pocketCredit}) approveSplit({
  required double reward,
  required int splitGoalPct,
  required double goalBank,
  required double targetAmount,
}) {
  final goalShare = reward * (splitGoalPct.clamp(0, 100) / 100.0);
  final pocketShare = reward - goalShare;
  final capped = splitCredit(
    amount: goalShare,
    goalBalance: goalBank,
    targetAmount: targetAmount,
  );
  return (
    goalCredit: capped.goalCredit,
    pocketCredit: _money(_cents(pocketShare) + _cents(capped.pocketCredit)),
  );
}

int _cents(double v) => (v * 100).round();
double _money(int c) => c / 100.0;

/// A kid may only submit with a photo when the chore demands one — and a
/// photo chore without a photo is blocked client-side AND at submit time.
void assertSubmittable({required bool requiresPhoto, required bool hasPhoto}) {
  if (requiresPhoto && !hasPhoto) {
    throw ArgumentError('This chore needs a photo before you can mark it done');
  }
}

/// Short, kind nudge shown on the Kid Today card for a rejected chore.
String rejectNudge({required String choreTitle, String? parentNote}) {
  if (parentNote != null && parentNote.trim().isNotEmpty) {
    return parentNote.trim();
  }
  return 'Try again with a clearer photo of the finished "$choreTitle"';
}

class ChoreService {
  ChoreService(this._clients);

  final RoleClients _clients;

  SupabaseClient get _parent => _clients.forRole(Role.parent);
  SupabaseClient get _kid => _clients.forRole(Role.kid);

  /// Read access for query extensions in `queries.dart`.
  SupabaseClient get parentClient => _parent;
  SupabaseClient get kidClient => _kid;

  /// Kid marks a chore done. Blocks photo-required chores without a photo.
  Future<void> submitChore({
    required String choreId,
    String? photoUrl,
  }) async {
    final chore = await _kid
        .from('chores')
        .select('requires_photo')
        .eq('id', choreId)
        .single();
    assertSubmittable(
      requiresPhoto: chore['requires_photo'] == true,
      hasPhoto: photoUrl != null,
    );
    await _kid.from('chore_submissions').insert({
      'chore_id': choreId,
      'photo_url': ?photoUrl,
    });
  }

  /// Parent approves: submission flips to approved and BOTH ledger entries
  /// (goal + pocket overshoot) are written by one atomic DB function, so the
  /// money rule cannot tear.
  Future<void> approveSubmission(String submissionId) async {
    await _parent.rpc('approve_chore_submission', params: {
      'p_submission_id': submissionId,
    });
  }

  /// Parent rejects with a nudge; the chore returns to Kid Today (rejected
  /// submissions are surfaced as retryable), and a retry inserts a new row.
  Future<void> rejectSubmission(String submissionId, String nudge) async {
    await _parent
        .from('chore_submissions')
        .update({
          'status': 'rejected',
          'reject_nudge': nudge,
          'decided_at': DateTime.now().toIso8601String(),
        })
        .eq('id', submissionId);
  }
}
