import 'chore_progress_math.dart';
import 'chore_service.dart';
import 'encouragement.dart';
import 'goal_service.dart';
import 'ledger_math.dart';

class KidChoreCard {
  final String id;
  final String title;
  final String cadence; // once | daily | weekly
  final double weightPct;
  final bool requiresPhoto;
  final bool isMakeup;
  final bool isBonus;
  final String? nudge; // rejected-with-nudge → retry prompt
  final String? latestStatus; // pending | approved | rejected | null
  final DateTime? latestCreatedAt;
  final String? libraryChoreId;
  final List<String> sharedChoreIds;
  final List<({double weightPct, String cadence, DateTime? latestAt})>
      creditMembers;

  const KidChoreCard({
    required this.id,
    required this.title,
    required this.cadence,
    required this.weightPct,
    required this.requiresPhoto,
    required this.isMakeup,
    required this.isBonus,
    this.nudge,
    this.latestStatus,
    this.latestCreatedAt,
    this.libraryChoreId,
    this.sharedChoreIds = const [],
    this.creditMembers = const [],
  });

  int get sharedGoalCount =>
      sharedChoreIds.isEmpty ? 1 : sharedChoreIds.length;

  KidRowKind rowKind(DateTime now) => kidRowKind(
        latestStatus: latestStatus,
        latestAt: latestCreatedAt,
        cadence: cadence,
        now: now,
      );

  String get cadenceLabel {
    switch (cadence) {
      case 'daily':
        return 'daily';
      case 'weekly':
        return 'weekly';
      default:
        return 'one time';
    }
  }
}

class PendingApproval {
  final String submissionId;
  final String choreTitle;
  final String cadence;
  final double weightPct;
  final bool requiresPhoto;
  final String? photoUrl;
  final String? libraryChoreId;
  final List<String> sharedSubmissionIds;

  const PendingApproval({
    required this.submissionId,
    required this.choreTitle,
    required this.cadence,
    required this.weightPct,
    required this.requiresPhoto,
    this.photoUrl,
    this.libraryChoreId,
    this.sharedSubmissionIds = const [],
  });

  int get sharedGoalCount =>
      sharedSubmissionIds.isEmpty ? 1 : sharedSubmissionIds.length;
}

extension ChoreServiceQueries on ChoreService {
  /// Kid Today: every active chore, annotated with a nudge when its latest
  /// submission was rejected. Makeup and bonus chores surface like any other.
  /// Chores of archived goals stay in the past - only active goals list.
  Future<List<KidChoreCard>> todayForKid() async {
    final rows = await kidClient
        .from('chores')
        .select('id, title, cadence, weight_pct, requires_photo, is_makeup, is_bonus, '
            'library_chore_id, '
            'chore_submissions(status, reject_nudge, created_at), goals!inner(status)')
        .eq('archived', false)
        .eq('goals.status', 'active')
        .order('created_at');
    return rows.map<KidChoreCard>((row) {
      final subs = (row['chore_submissions'] as List?) ?? const [];
      String? nudge;
      String? latestStatus;
      DateTime? latestCreatedAt;
      if (subs.isNotEmpty) {
        final sorted = [...subs]
          ..sort((a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String));
        final latest = sorted.first;
        latestStatus = latest['status'] as String?;
        final created = latest['created_at'] as String?;
        if (created != null) latestCreatedAt = DateTime.parse(created);
        if (latestStatus == 'rejected') {
          nudge = latest['reject_nudge'] as String?;
        }
      }
      return KidChoreCard(
        id: row['id'] as String,
        title: row['title'] as String,
        cadence: row['cadence'] as String,
        weightPct: (row['weight_pct'] as num).toDouble(),
        requiresPhoto: row['requires_photo'] == true,
        isMakeup: row['is_makeup'] == true,
        isBonus: row['is_bonus'] == true,
        nudge: nudge,
        latestStatus: latestStatus,
        latestCreatedAt: latestCreatedAt,
        libraryChoreId: row['library_chore_id'] as String?,
      );
    }).toList();
  }

  /// Parent approval inbox: pending submissions with chore info and the %
  /// credit this approval would add.
  Future<List<PendingApproval>> pendingForParent() async {
    final rows = await parentClient
        .from('chore_submissions')
        .select('id, photo_url, chore_id, chores(title, cadence, weight_pct, requires_photo, library_chore_id)')
        .eq('status', 'pending')
        .order('created_at');
    return rows.map<PendingApproval>((row) {
      final chore = row['chores'] as Map<String, dynamic>;
      return PendingApproval(
        submissionId: row['id'] as String,
        choreTitle: chore['title'] as String,
        cadence: chore['cadence'] as String,
        weightPct: (chore['weight_pct'] as num).toDouble(),
        requiresPhoto: chore['requires_photo'] == true,
        photoUrl: row['photo_url'] as String?,
        libraryChoreId: chore['library_chore_id'] as String?,
      );
    }).toList();
  }

  /// % this approval would credit the kid (weight / expected instances).
  double creditPreview(PendingApproval p, int weeksN) {
    final expected = expectedInstances(cadence: p.cadence, weeksN: weeksN);
    return instanceCreditPct(weightPct: p.weightPct, expectedInstances: expected);
  }
}

class GoalProgressView {
  final String id;
  final String title;
  final double targetAmount; // parent cost
  final String goalMode; // family_trip | kid_item
  final bool allowMakeup;
  final DateTime? targetDate;
  final int weeksN;
  final double choreProgressPct; // kid %, capped at 100
  final double parentSaved; // sum of logged parent saves
  final double planWeightSum; // sum of chore weights (may exceed 100)
  final double weeklyParentSave; // accepted plan, or computed fallback

  final int weeksElapsed; // whole weeks since created_at (0 at creation)

  GoalProgressView({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.goalMode,
    required this.allowMakeup,
    required this.targetDate,
    required this.weeksN,
    required this.choreProgressPct,
    required this.parentSaved,
    required this.planWeightSum,
    required this.weeklyParentSave,
    this.weeksElapsed = 0,
  });

  double get parentSaveFraction =>
      parentSaveProgress(saved: parentSaved, cost: targetAmount);

  /// What the parent must save per remaining week from today's balance.
  /// The accepted plan's [weeklyParentSave] is frozen; this moves.
  double get requiredWeeklyNow =>
      requiredWeeklySave(target: targetAmount, saved: parentSaved, weeksN: weeksN);

  /// Parent behind on money: the honest catch-up rate now exceeds the plan's
  /// weekly figure (0.01 tolerance absorbs numeric rounding).
  bool get parentBehind => requiredWeeklyNow > weeklyParentSave + 0.01;

  /// Kid behind pace, driven by real elapsed weeks (not the POC knob):
  /// linear projection of chore progress misses 100 by the target date.
  bool get kidBehindPace => isBehindPace(
        progressPct: choreProgressPct,
        weeksN: weeksN,
        weeksElapsed: weeksElapsed,
        planWeightSum: planWeightSum,
      );

  /// Behind pace = linear projection misses 100 by the target date.
  bool behindPace({required int weeksElapsed}) => isBehindPace(
        progressPct: choreProgressPct,
        weeksN: weeksN,
        weeksElapsed: weeksElapsed,
        planWeightSum: planWeightSum,
      );
}

extension GoalServiceQueries on GoalService {
  /// Parent home: chore-% progress plus the parent save log.
  Future<List<GoalProgressView>> goalsWithProgress() =>
      _loadGoals(parentClient);

  /// Kid summary: same source numbers, but the kid UI only ever renders the %.
  Future<List<GoalProgressView>> kidGoalSummary() => _loadGoals(kidClient);

  Future<List<GoalProgressView>> _loadGoals(dynamic client) async {
    final goals = await client
        .from('goals')
        .select('id, title, target_amount, target_date, goal_mode, allow_makeup, created_at')
        .eq('status', 'active')
        .order('created_at');

    final views = <GoalProgressView>[];
    for (final g in goals) {
      final goalId = g['id'] as String;
      final createdAt = DateTime.parse(g['created_at'] as String);
      // Whole elapsed weeks since the goal started (for pace checks).
      final elapsed =
          DateTime.now().difference(createdAt).inDays ~/ 7;

      final chores = await client
          .from('chores')
          .select('cadence, weight_pct, chore_submissions(status)')
          .eq('goal_id', goalId)
          .eq('archived', false);

      final specs = <({double weightPct, String cadence, int approvedCount})>[];
      var weightSum = 0.0;
      for (final c in chores) {
        final cadence = c['cadence'] as String;
        final weight = (c['weight_pct'] as num).toDouble();
        weightSum += weight;
        final subs = (c['chore_submissions'] as List?) ?? const [];
        final approved = subs.where((s) => s['status'] == 'approved').length;
        specs.add((
          weightPct: weight,
          cadence: cadence,
          approvedCount: approved,
        ));
      }

      final targetDate = g['target_date'] == null
          ? null
          : DateTime.parse(g['target_date'] as String);
      final n = targetDate == null
          ? 1
          : weeksRemaining(today: DateTime.now(), targetDate: targetDate);

      final saves = await client
          .from('parent_save_entries')
          .select('amount')
          .eq('goal_id', goalId);
      // Postgres numerics decode as int when integral; accumulate through num
      // (a generic fold on a dynamic receiver keeps its int seed and throws).
      var saved = 0.0;
      for (final e in saves) {
        saved += (e['amount'] as num).toDouble();
      }

      final plans = await client
          .from('ai_plans')
          .select('suggestion')
          .eq('goal_id', goalId)
          .eq('accepted', true)
          .order('created_at', ascending: false)
          .limit(1);
      final weeklySave = plans.isNotEmpty
          ? ((plans.first['suggestion'] as Map<String,
                      dynamic>)['weekly_parent_save'] as num?)
                  ?.toDouble() ??
              suggestedSavePerWeek(
                  cost: (g['target_amount'] as num).toDouble(), weeksN: n)
          : suggestedSavePerWeek(
              cost: (g['target_amount'] as num).toDouble(), weeksN: n);

      views.add(GoalProgressView(
        weeksElapsed: elapsed,
        id: goalId,
        title: g['title'] as String,
        targetAmount: (g['target_amount'] as num).toDouble(),
        goalMode: g['goal_mode'] as String,
        allowMakeup: g['allow_makeup'] == true,
        targetDate: targetDate,
        weeksN: n,
        choreProgressPct: kidProgressPct(chores: specs, weeksN: n),
        parentSaved: saved,
        planWeightSum: weightSum,
        weeklyParentSave: weeklySave,
      ));
    }
    return views;
  }
}

/// One visible Today row per library id. Null library id never merges.
List<KidChoreCard> collapseTodayByLibraryId(
  List<KidChoreCard> chores, {
  required DateTime now,
}) {
  final groups = <String, List<KidChoreCard>>{};
  for (final c in chores) {
    final id = c.libraryChoreId;
    if (id == null || id.isEmpty) continue;
    groups.putIfAbsent(id, () => []).add(c);
  }
  final seen = <String>{};
  final out = <KidChoreCard>[];
  for (final c in chores) {
    final id = c.libraryChoreId;
    if (id == null || id.isEmpty) {
      out.add(c);
      continue;
    }
    if (!seen.add(id)) continue;
    final members = groups[id]!;
    out.add(members.length == 1 ? members.first : _mergeToday(members, id, now));
  }
  return out;
}

KidChoreCard _mergeToday(
  List<KidChoreCard> members,
  String libraryId,
  DateTime now,
) {
  var lead = members.first;
  var leadRank = _kindRank(lead.rowKind(now));
  for (final m in members.skip(1)) {
    final rank = _kindRank(m.rowKind(now));
    if (rank < leadRank) {
      lead = m;
      leadRank = rank;
    }
  }
  return KidChoreCard(
    id: lead.id,
    title: lead.title,
    cadence: lead.cadence,
    weightPct: lead.weightPct,
    requiresPhoto: members.any((m) => m.requiresPhoto),
    isMakeup: members.every((m) => m.isMakeup),
    isBonus: members.every((m) => m.isBonus),
    nudge: lead.nudge,
    latestStatus: lead.latestStatus,
    latestCreatedAt: lead.latestCreatedAt,
    libraryChoreId: libraryId,
    sharedChoreIds: [for (final m in members) m.id],
    creditMembers: [
      for (final m in members)
        (
          weightPct: m.weightPct,
          cadence: m.cadence,
          latestAt: m.latestCreatedAt,
        )
    ],
  );
}

int _kindRank(KidRowKind k) {
  switch (k) {
    case KidRowKind.open:
      return 0;
    case KidRowKind.nextTry:
      return 1;
    case KidRowKind.sent:
      return 2;
  }
}

List<String> submissionChoreIds(KidChoreCard c) {
  if (c.sharedChoreIds.isEmpty) return [c.id];
  return [for (final id in {c.id, ...c.sharedChoreIds}) id];
}

List<({double weightPct, String cadence, DateTime? latestAt})>
    slicesForDayDone(KidChoreCard c) {
  if (c.creditMembers.isNotEmpty) return c.creditMembers;
  return [
    (
      weightPct: c.weightPct,
      cadence: c.cadence,
      latestAt: c.latestCreatedAt,
    )
  ];
}

List<PendingApproval> collapsePendingByLibraryId(List<PendingApproval> items) {
  final groups = <String, List<PendingApproval>>{};
  for (final p in items) {
    final id = p.libraryChoreId;
    if (id == null || id.isEmpty) continue;
    groups.putIfAbsent(id, () => []).add(p);
  }
  final seen = <String>{};
  final out = <PendingApproval>[];
  for (final p in items) {
    final id = p.libraryChoreId;
    if (id == null || id.isEmpty) {
      out.add(p);
      continue;
    }
    if (!seen.add(id)) continue;
    final members = groups[id]!;
    out.add(members.length == 1 ? members.first : _mergePending(members, id));
  }
  return out;
}

PendingApproval _mergePending(List<PendingApproval> members, String libraryId) {
  final lead = members.first;
  return PendingApproval(
    submissionId: lead.submissionId,
    choreTitle: lead.choreTitle,
    cadence: lead.cadence,
    weightPct: lead.weightPct,
    requiresPhoto: members.any((m) => m.requiresPhoto),
    photoUrl: lead.photoUrl ??
        members
            .map((m) => m.photoUrl)
            .firstWhere((u) => u != null, orElse: () => null),
    libraryChoreId: libraryId,
    sharedSubmissionIds: [for (final m in members) m.submissionId],
  );
}

List<String> clusterSubmissionIds(PendingApproval p) {
  if (p.sharedSubmissionIds.isEmpty) return [p.submissionId];
  return [for (final id in {p.submissionId, ...p.sharedSubmissionIds}) id];
}
