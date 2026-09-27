import 'chore_service.dart';
import 'goal_service.dart';
import 'ledger_math.dart';

class KidChoreCard {
  final String id;
  final String title;
  final double reward;
  final bool requiresPhoto;
  final int splitGoalPct;
  final String? nudge; // rejected-with-nudge → retry prompt

  const KidChoreCard({
    required this.id,
    required this.title,
    required this.reward,
    required this.requiresPhoto,
    required this.splitGoalPct,
    this.nudge,
  });
}

class PendingApproval {
  final String submissionId;
  final String choreTitle;
  final double reward;
  final bool requiresPhoto;
  final String? photoUrl;

  const PendingApproval({
    required this.submissionId,
    required this.choreTitle,
    required this.reward,
    required this.requiresPhoto,
    this.photoUrl,
  });
}

extension ChoreServiceQueries on ChoreService {
  /// Kid Today: every active chore, annotated with a nudge when its latest
  /// submission was rejected.
  Future<List<KidChoreCard>> todayForKid() async {
    final rows = await kidClient
        .from('chores')
        .select('id, title, reward_amount, default_split_goal_pct, requires_photo, '
            'chore_submissions(status, reject_nudge, created_at)')
        .eq('archived', false)
        .order('created_at');
    return rows.map<KidChoreCard>((row) {
      final subs = (row['chore_submissions'] as List?) ?? const [];
      String? nudge;
      if (subs.isNotEmpty) {
        subs.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
        final latest = subs.first;
        if (latest['status'] == 'rejected') nudge = latest['reject_nudge'] as String?;
      }
      return KidChoreCard(
        id: row['id'] as String,
        title: row['title'] as String,
        reward: (row['reward_amount'] as num).toDouble(),
        requiresPhoto: row['requires_photo'] == true,
        splitGoalPct: row['default_split_goal_pct'] as int,
        nudge: nudge,
      );
    }).toList();
  }

  /// Parent approval inbox: pending submissions with chore info.
  Future<List<PendingApproval>> pendingForParent() async {
    final rows = await parentClient
        .from('chore_submissions')
        .select('id, photo_url, chore_id, chores(title, reward_amount, requires_photo)')
        .eq('status', 'pending')
        .order('created_at');
    return rows.map<PendingApproval>((row) {
      final chore = row['chores'] as Map<String, dynamic>;
      return PendingApproval(
        submissionId: row['id'] as String,
        choreTitle: chore['title'] as String,
        reward: (chore['reward_amount'] as num).toDouble(),
        requiresPhoto: chore['requires_photo'] == true,
        photoUrl: row['photo_url'] as String?,
      );
    }).toList();
  }
}

class GoalProgressView {
  final String id;
  final String title;
  final double targetAmount;
  final double goalBank;
  final double pocket;
  final double weeklyTopup;

  const GoalProgressView({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.goalBank,
    required this.pocket,
    required this.weeklyTopup,
  });

  double get progress => goalProgress(goalBank: goalBank, targetAmount: targetAmount);
  int? get weeksLeft => weeksToGoal(
      goalBank: goalBank, targetAmount: targetAmount, weeklyTopup: weeklyTopup);
}

extension GoalServiceQueries on GoalService {
  /// Kid's goal-vs-pocket view (all reads under the kid JWT).
  Future<List<GoalProgressView>> kidGoalSummary() async {
    final goals = await kidClient
        .from('goals')
        .select('id, title, target_amount')
        .eq('status', 'active')
        .order('created_at');
    final kid = kidClient;
    final views = <GoalProgressView>[];
    for (final g in goals) {
      final entries = await kid
          .from('ledger_entries')
          .select('kind, amount')
          .eq('goal_id', g['id']);
      final summary = sumLedger(entries
          .map<LedgerEntry>((e) => LedgerEntry(
                kind: e['kind'] == 'pocket_credit'
                    ? LedgerKind.pocketCredit
                    : LedgerKind.goalCredit,
                amount: (e['amount'] as num).toDouble(),
              ))
          .toList());
      views.add(GoalProgressView(
        id: g['id'] as String,
        title: g['title'] as String,
        targetAmount: (g['target_amount'] as num).toDouble(),
        goalBank: summary.goalBank,
        pocket: summary.pocket,
        weeklyTopup: 0,
      ));
    }
    return views;
  }

  /// Parent home: goals with ledger-derived balances and the accepted plan's
  /// weekly top-up. Balances are always computed on read — never stored.
  Future<List<GoalProgressView>> goalsWithProgress() async {
    final goals = await parentClient
        .from('goals')
        .select('id, title, target_amount')
        .eq('status', 'active')
        .order('created_at');
    final plans = await parentClient
        .from('ai_plans')
        .select('goal_id, suggestion')
        .eq('accepted', true);

    double topupFor(String goalId) {
      for (final p in plans) {
        if (p['goal_id'] == goalId) {
          return ((p['suggestion'] as Map<String, dynamic>)['weekly_topup'] as num?)?.toDouble() ?? 0;
        }
      }
      return 0;
    }

    final views = <GoalProgressView>[];
    for (final g in goals) {
      final entries = await parentClient
          .from('ledger_entries')
          .select('kind, amount')
          .eq('goal_id', g['id']);
      final summary = sumLedger(entries
          .map<LedgerEntry>((e) => LedgerEntry(
                kind: e['kind'] == 'pocket_credit'
                    ? LedgerKind.pocketCredit
                    : LedgerKind.goalCredit,
                amount: (e['amount'] as num).toDouble(),
              ))
          .toList());
      views.add(GoalProgressView(
        id: g['id'] as String,
        title: g['title'] as String,
        targetAmount: (g['target_amount'] as num).toDouble(),
        goalBank: summary.goalBank,
        pocket: summary.pocket,
        weeklyTopup: topupFor(g['id'] as String),
      ));
    }
    return views;
  }
}
