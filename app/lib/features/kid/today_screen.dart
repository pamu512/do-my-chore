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
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kid Today')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          ..._goals.map(_goalHero),
          const SizedBox(height: 6),
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
      ),
    );
  }

  Widget _goalHero(GoalProgressView g) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OUR GOAL', style: Dmc.micro),
            const SizedBox(height: 3),
            Text(g.title, style: Dmc.displayStyle(size: 23, weight: FontWeight.w700)),
            const SizedBox(height: 14),
            DmcProgressRail(
              pct: g.choreProgressPct,
              isKid: true,
              leftCap: '0%',
              rightCap: '100%',
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                text: '${g.choreProgressPct.toStringAsFixed(0)}%',
                style: Dmc.displayStyle(size: 30, weight: FontWeight.w700, color: Dmc.marigoldDeep),
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
              'Keep the habits going. 100% earns the '
              '${g.goalMode == 'family_trip' ? 'trip' : 'reward'}.',
              style: TextStyle(fontSize: 13, height: 1.45, color: Dmc.muted),
            ),
          ],
        ),
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
                    '${c.cadenceLabel} · worth +${c.weightPct.toStringAsFixed(0)}%',
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
}
