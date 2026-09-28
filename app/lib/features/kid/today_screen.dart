import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../../services/queries.dart';
import 'mark_done_screen.dart';

/// Kid Today: chores (with rejected-nudge retries) and the goal rail in
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
    final c = await chores.todayForKid();
    final g = await goals.kidGoalSummary();
    if (mounted) {
      setState(() {
        _chores = c;
        _goals = g;
        _loading = false;
      });
    }
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_goals.isEmpty)
            const _NoGoalCard()
          else
            ..._goals.map(_goalHero),
          const SizedBox(height: 6),
          if (_chores.isEmpty)
            const _NoChoresCard()
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
              child: Row(
                children: [
                  Text("TODAY'S CHORES", style: Dmc.micro),
                  const Spacer(),
                  Text(
                    'Tap one when it\'s done',
                    style: TextStyle(fontSize: 12, color: Dmc.faint),
                  ),
                ],
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _chores.length; i++)
                    _choreRow(context, _chores[i], i + 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _goalHero(GoalProgressView g) {
    final pct = g.choreProgressPct;
    final earned = pct >= 100 - 1e-9;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Castle hero: the shared dream at the top of the kid's day.
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
                ),
                // Porcelain scrim so white type stays AA on any photo.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0x331F2621),
                        const Color(0xB31F2621),
                      ],
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
                    children: [
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
                  earned
                      ? 'You earned it. Talk to your parent about the ${g.goalMode == 'family_trip' ? 'trip' : 'reward'}.'
                      : 'Keep the habits going. 100% earns the '
                          '${g.goalMode == 'family_trip' ? 'trip' : 'reward'}.',
                  style:
                      TextStyle(fontSize: 13, height: 1.45, color: Dmc.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choreRow(BuildContext context, KidChoreCard c, int n) {
    final retry = c.nudge != null;
    return InkWell(
      onTap: () async {
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
        _refresh();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Dmc.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text('$n'.padLeft(2, '0'),
                  style: TextStyle(fontSize: 12, color: Dmc.faint)),
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
                          c.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Dmc.ink,
                          ),
                        ),
                      ),
                      if (c.requiresPhoto) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.photo_camera_outlined,
                            size: 15, color: Dmc.faint),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _choreMeta(c),
                    style: TextStyle(fontSize: 12.5, color: Dmc.muted),
                  ),
                  if (retry)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(
                        color: Dmc.marigoldSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Try again - ${c.nudge}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: const Color(0xFF6B4A15),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (retry)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Dmc.marigoldSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFEBD9BC)),
                ),
                child: Text(
                  'TRY AGAIN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: const Color(0xFF6B4A15),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, size: 18, color: Dmc.faint),
              ),
          ],
        ),
      ),
    );
  }

  String _choreMeta(KidChoreCard c) {
    if (c.isMakeup) return 'Makeup chore · catches you up';
    if (c.isBonus) return 'Bonus chore · extra points';
    switch (c.cadence) {
      case 'daily':
        return 'Every day · earns up to ${c.weightPct.toStringAsFixed(0)}%';
      case 'weekly':
        return 'Every week · earns up to ${c.weightPct.toStringAsFixed(0)}%';
      default:
        return 'One time · earns ${c.weightPct.toStringAsFixed(0)}%';
    }
  }
}

/// Warm empty state: no active goal yet (parent hasn't set one).
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
            Text(
              'Ask your parent to set one up.',
              style: TextStyle(fontSize: 13, color: Dmc.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state: goal exists but no chores are assigned today.
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
            Text(
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
