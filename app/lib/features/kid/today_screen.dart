import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/chore_progress_math.dart';
import '../../services/chore_service.dart';
import '../../services/encouragement.dart';
import '../../services/goal_service.dart';
import '../../services/queries.dart';
import 'encouragement_widgets.dart';
import 'mark_done_screen.dart';

/// Kid Today: chores (with next-try notes) and the goal rail in
/// percent only. No dollars, no pocket: earning the goal is a habit streak;
/// the money side lives on the parent's planner screens.
class KidTodayScreen extends StatefulWidget {
  const KidTodayScreen({super.key, this.choreService, this.goalService});

  final ChoreService? choreService;
  final GoalService? goalService;

  @override
  State<KidTodayScreen> createState() => _KidTodayScreenState();
}

class _KidTodayScreenState extends State<KidTodayScreen> {
  bool _loading = true;
  List<KidChoreCard> _chores = const [];
  List<GoalProgressView> _goals = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final chores = widget.choreService;
    final goals = widget.goalService;
    if (chores == null || goals == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final c = await chores.todayForKid();
      final g = await goals.kidGoalSummary();
      if (mounted) {
        setState(() {
          _chores = c;
          _goals = g;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load today: $e')),
        );
      }
    }
  }

  Future<void> _open(KidChoreCard c) async {
    if (widget.choreService == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarkDoneScreen(
          service: widget.choreService!,
          chore: c,
          weeksN: _goals.isNotEmpty ? _goals.first.weeksN : null,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kid Today')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: const [
            DmcGoalCardSkeleton(),
            SizedBox(height: 16),
            DmcSkeleton(height: 11, margin: EdgeInsets.symmetric(vertical: 10)),
            SizedBox(height: 8),
            DmcSkeleton(height: 96),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kid Today')),
      body: KidTodayBody(
        chores: _chores,
        goals: _goals,
        now: DateTime.now(),
        onOpen: _open,
      ),
    );
  }
}

/// Presentational Today list. Tests pump this without Supabase.
class KidTodayBody extends StatelessWidget {
  const KidTodayBody({
    super.key,
    required this.chores,
    required this.goals,
    required this.now,
    this.onOpen,
  });

  final List<KidChoreCard> chores;
  final List<GoalProgressView> goals;
  final DateTime now;
  final ValueChanged<KidChoreCard>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (goals.isNotEmpty && goals.first.choreProgressPct >= 100 - 1e-9) {
      final g = goals.first;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          KidGoalEarnedFinale(
            goalTitle: g.title,
            handOff: earnedHandOff(goalMode: g.goalMode),
          ),
        ],
      );
    }

    final visible = collapseTodayByLibraryId(chores, now: now);
    final kinds = visible.map((c) => c.rowKind(now)).toList();
    final dayDone = allSent(kinds);
    final g = goals.isNotEmpty ? goals.first : null;
    final behind = g?.kidBehindPace == true;
    final openChores = [
      for (var i = 0; i < visible.length; i++)
        if (kinds[i] == KidRowKind.open) visible[i]
    ];
    final showPace = behind && openChores.isNotEmpty && !dayDone;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (goals.isEmpty)
          const _NoGoalCard()
        else
          ...goals.map(_goalHero),
        if (showPace && g != null) ...[
          const SizedBox(height: 2),
          KidPaceCard(
            title: paceCardTitle(_checkInsNeeded(g, openChores)),
            body: paceCardBody(openChores.map((c) => c.title).toList()),
          ),
        ],
        if (dayDone) ...[
          const SizedBox(height: 8),
          KidDayDoneCard(
            movedPct: todayMovedPct(
              chores: [
                for (final c in visible) ...slicesForDayDone(c)
              ],
              weeksN: g?.weeksN ?? 1,
              now: now,
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (visible.isEmpty)
          const _NoChoresCard()
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Row(
              children: [
                Text("TODAY'S CHORES", style: Dmc.micro),
                const Spacer(),
                Text(
                  dayDone ? 'Waiting on your parent' : 'Tap one when it\'s done',
                  style: const TextStyle(fontSize: 12, color: Dmc.faint),
                ),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++)
                  _KidChoreRow(
                    chore: visible[i],
                    index: i + 1,
                    kind: kinds[i],
                    onOpen: onOpen,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  int _checkInsNeeded(GoalProgressView g, List<KidChoreCard> open) {
    final credits = open.map((c) {
      final expected =
          expectedInstances(cadence: c.cadence, weeksN: g.weeksN);
      return instanceCreditPct(
          weightPct: c.weightPct, expectedInstances: expected);
    }).toList()
      ..sort((a, b) => b.compareTo(a));
    return checkInsToOnPace(
      progressPct: g.choreProgressPct,
      weeksN: g.weeksN,
      weeksElapsed: g.weeksElapsed,
      openCreditsDesc: credits,
    );
  }

  Widget _goalHero(GoalProgressView g) {
    final pct = g.choreProgressPct;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/photos/castle.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Dmc.pineDeep),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x331F2621), Color(0xB31F2621)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'OUR GOAL',
                        style: Dmc.micro.copyWith(
                          color: const Color(0xFFE9E4D8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Dmc.displayStyle(
                          size: 23,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DmcProgressRail(
                  pct: pct,
                  isKid: true,
                  leftCap: '0%',
                  rightCap: '100%',
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    text: '${pct.toStringAsFixed(0)}%',
                    style: Dmc.displayStyle(
                        size: 30,
                        weight: FontWeight.w700,
                        color: Dmc.marigoldDeep),
                    children: const [
                      TextSpan(
                        text: ' of the way there',
                        style: TextStyle(
                          fontFamily: Dmc.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Dmc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  kidHeroLine(
                    behindPace: g.kidBehindPace,
                    goalMode: g.goalMode,
                  ),
                  style:
                      const TextStyle(fontSize: 13, height: 1.45, color: Dmc.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KidChoreRow extends StatelessWidget {
  const _KidChoreRow({
    required this.chore,
    required this.index,
    required this.kind,
    this.onOpen,
  });

  final KidChoreCard chore;
  final int index;
  final KidRowKind kind;
  final ValueChanged<KidChoreCard>? onOpen;

  @override
  Widget build(BuildContext context) {
    final sent = kind == KidRowKind.sent;
    final next = kind == KidRowKind.nextTry;
    final tappable = !sent && onOpen != null;
    return InkWell(
      onTap: tappable ? () => onOpen!(chore) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: sent ? Dmc.pineSoft : null,
          border: const Border(top: BorderSide(color: Dmc.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text('$index'.padLeft(2, '0'),
                  style: const TextStyle(fontSize: 12, color: Dmc.faint)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chore.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: sent ? Dmc.pineDeep : Dmc.ink,
                          ),
                        ),
                      ),
                      if (chore.requiresPhoto && !sent) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.photo_camera_outlined,
                            size: 15, color: Dmc.faint),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _choreMeta(chore),
                    style: const TextStyle(fontSize: 12.5, color: Dmc.muted),
                  ),
                  if (next && chore.nudge != null)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Dmc.marigoldSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEBD9BC)),
                      ),
                      child: Text(
                        chore.nudge!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFF6B4A15),
                        ),
                      ),
                    ),
                  if (sent) ...[
                    const SizedBox(height: 4),
                    const KidSentChip(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (next)
              const KidNextTryBadge()
            else if (!sent)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, size: 18, color: Dmc.faint),
              ),
          ],
        ),
      ),
    );
  }
}

String _choreMeta(KidChoreCard c) {
  if (c.isMakeup) return 'Makeup chore · extra check-in';
  if (c.isBonus) return 'Bonus chore · extra points';
  if (c.sharedGoalCount > 1) {
    switch (c.cadence) {
      case 'daily':
        return 'Every day · counts for ${c.sharedGoalCount} goals';
      case 'weekly':
        return 'Every week · counts for ${c.sharedGoalCount} goals';
      default:
        return 'One time · counts for ${c.sharedGoalCount} goals';
    }
  }
  switch (c.cadence) {
    case 'daily':
      return 'Every day · earns up to ${c.weightPct.toStringAsFixed(0)}%';
    case 'weekly':
      return 'Every week · earns up to ${c.weightPct.toStringAsFixed(0)}%';
    default:
      return 'One time · earns ${c.weightPct.toStringAsFixed(0)}%';
  }
}

class _NoGoalCard extends StatelessWidget {
  const _NoGoalCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Dmc.marigoldSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag_outlined,
                  size: 22, color: Dmc.marigoldDeep),
            ),
            const SizedBox(height: 12),
            Text('No goal yet',
                style: Dmc.displayStyle(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'Ask your parent to set one up.',
              style: TextStyle(fontSize: 13, color: Dmc.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoChoresCard extends StatelessWidget {
  const _NoChoresCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Dmc.pineSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_outlined,
                  size: 22, color: Dmc.pine),
            ),
            const SizedBox(height: 12),
            Text('All clear today',
                style: Dmc.displayStyle(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'New chores appear when your parent adds them.',
              style: TextStyle(fontSize: 13, color: Dmc.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
