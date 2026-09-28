import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/album_service.dart';
import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../../services/queries.dart';
import 'album_screen.dart';
import 'approvals_screen.dart';
import 'new_goal_screen.dart';

/// Parent home: the financial planner. Parent sees the real cost, the save
/// cadence, and the kid's habit progress in percent. Makeup chores appear
/// only when the goal allows them and the kid is behind pace.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({
    super.key,
    this.goalService,
    this.choreService,
    this.albumService,
  });

  final GoalService? goalService;
  final ChoreService? choreService;
  final AlbumService? albumService;

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  bool _loading = true;
  List<GoalProgressView> _goals = const [];
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final goals = widget.goalService;
    final chores = widget.choreService;
    if (goals == null || chores == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final g = await goals.goalsWithProgress();
    final p = await chores.pendingForParent();
    if (mounted) {
      setState(() {
        _goals = g;
        _pending = p.length;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Parent Home')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: const [
            DmcSkeleton(height: 54, radius: 10),
            SizedBox(height: 16),
            DmcGoalCardSkeleton(),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Home')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _privacyBanner(),
          const SizedBox(height: 12),
          if (widget.choreService != null) _approvalsCard(context),
          if (widget.choreService != null) const SizedBox(height: 16),
          if (_goals.isEmpty && widget.goalService != null)
            _noGoalsCard()
          else
            ..._goals.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _goalCard(context, g),
                )),
          if (widget.goalService != null)
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          NewGoalScreen(goalService: widget.goalService!)),
                );
                _refresh();
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New Goal'),
            ),
        ],
      ),
    );
  }

  /// First-run state: no goal yet, planner invites the parent in.
  Widget _noGoalsCard() {
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
              child: const Icon(Icons.flag_outlined, size: 22, color: Dmc.pine),
            ),
            const SizedBox(height: 12),
            Text('No goal yet',
                style: Dmc.displayStyle(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Set one up below - the app does the save math for you.',
              style: TextStyle(fontSize: 13, color: Dmc.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _privacyBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Dmc.cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Dmc.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: Dmc.faint),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'The app plans the money; you move it yourself. '
              'Photos in this demo are test data only.',
              style: TextStyle(
                fontFamily: Dmc.text,
                fontSize: 12.5,
                height: 1.45,
                color: Dmc.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _approvalsCard(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ApprovalsScreen(
                service: widget.choreService!,
                weeksN: _goals.isNotEmpty ? _goals.first.weeksN : null,
              ),
            ),
          );
          _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Dmc.pineSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.inbox_outlined, size: 20, color: Dmc.pine),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_pending chore${_pending == 1 ? '' : 's'} waiting for approval',
                      style: TextStyle(
                        fontFamily: Dmc.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Dmc.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Photo check-ins from Arjun',
                      style: TextStyle(fontSize: 12.5, color: Dmc.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Dmc.faint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalCard(BuildContext context, GoalProgressView g) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('CURRENT GOAL', style: Dmc.micro),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Dmc.cream,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Dmc.line),
                  ),
                  child: Text(
                    g.goalMode == 'family_trip' ? 'TRIP' : 'ITEM',
                    style: TextStyle(
                      fontFamily: Dmc.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                      color: Dmc.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Dmc.line),
                  ),
                  child: Image.asset(
                    'assets/photos/castle.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Dmc.marigoldSoft,
                      child: const Icon(Icons.castle_outlined,
                          size: 22, color: Dmc.faint),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(g.title,
                      style:
                          Dmc.displayStyle(size: 23, weight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // The money plan: real dollars, parent's side of the ledger.
            Text.rich(
              TextSpan(
                text:
                    '\$${g.parentSaved.toStringAsFixed(0)}',
                style: Dmc.displayStyle(size: 28, weight: FontWeight.w700),
                children: [
                  TextSpan(
                    text: ' of \$${g.targetAmount.toStringAsFixed(0)} saved',
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
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: g.parentSaveFraction.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Dmc.line,
                valueColor: const AlwaysStoppedAnimation(Dmc.pine),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'About \$${g.weeklyParentSave.toStringAsFixed(0)}/week for ${g.weeksN} weeks',
              style: TextStyle(fontSize: 13, color: Dmc.muted),
            ),
            const Divider(height: 26),
            Row(
              children: [
                Text('Arjun\'s chore progress', style: TextStyle(fontSize: 14, color: Dmc.ink2)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Dmc.cream,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Dmc.line),
                  ),
                  child: Text(
                    '${g.choreProgressPct.toStringAsFixed(0)}% there',
                    style: TextStyle(
                      fontFamily: Dmc.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Dmc.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DmcProgressRail(
              pct: g.choreProgressPct,
              isKid: false,
              leftCap: '0%',
              rightCap: '100% earns the '
                  '${g.goalMode == 'family_trip' ? 'trip' : 'reward'}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _logSave(g),
                  icon: const Icon(Icons.savings_outlined, size: 17),
                  label: const Text('I saved this week'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.albumService == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AlbumScreen(
                                    service: widget.albumService!,
                                    goalId: g.id,
                                    choreService: widget.choreService)),
                          ),
                  icon: const Icon(Icons.photo_album_outlined, size: 17),
                  label: const Text('Goal Album'),
                ),
              ],
            ),
            if (g.parentBehind) ...[
              const SizedBox(height: 4),
              _catchUpCard(g),
            ],
            if (g.kidBehindPace) ...[
              const SizedBox(height: 8),
              _kidPaceCard(context, g),
            ],
          ],
        ),
      ),
    );
  }

  /// Parent side: the honest weekly rate has climbed above the plan.
  Widget _catchUpCard(GoalProgressView g) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Dmc.marigoldSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEBD9BC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, size: 18, color: Dmc.marigoldDeep),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                text:
                    'Now \$${g.requiredWeeklyNow.toStringAsFixed(0)}/wk ',
                style: TextStyle(
                    fontFamily: Dmc.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Dmc.ink),
                children: [
                  TextSpan(
                    text:
                        'to stay on track (plan was \$${g.weeklyParentSave.toStringAsFixed(0)}/wk).',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Dmc.marigoldDeep),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Kid side: behind pace. Both options live here - makeup chores (when the
  /// goal allows them) or ending the goal. Ending is guarded server-side:
  /// the RPC refuses if the kid is on pace or has already earned the goal.
  Widget _kidPaceCard(BuildContext context, GoalProgressView g) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Dmc.claySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8CFC7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: Dmc.clayText),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Behind pace',
                        style: TextStyle(
                            fontFamily: Dmc.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Dmc.ink)),
                    Text(
                      'At this rate the goal is out of reach by the target date.',
                      style:
                          TextStyle(fontSize: 12.5, color: Dmc.clayText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (g.allowMakeup)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _addMakeup(g),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      foregroundColor: Dmc.clayText,
                      side: const BorderSide(color: Color(0xFFE3C4BA)),
                    ),
                    child: const Text('Add makeup chore',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              if (g.allowMakeup) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmEndGoal(g),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    foregroundColor: Dmc.clayText,
                    side: const BorderSide(color: Color(0xFFE3C4BA)),
                  ),
                  child: const Text('End goal',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEndGoal(GoalProgressView g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this goal?'),
        content: Text(
          'The goal will move out of both homes. This cannot be undone. '
          'If the kid is keeping pace, the app will not allow it.',
          style: TextStyle(fontSize: 14, height: 1.5, color: Dmc.ink2),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Dmc.clay),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End goal')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.goalService!.endGoal(goalId: g.id);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not end goal: $e')));
      }
    }
  }

  Future<void> _logSave(GoalProgressView g) async {
    final controller = TextEditingController(
        text: g.weeklyParentSave.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log a save'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Amount (\$)', prefixText: '\$'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, double.tryParse(controller.text)),
              child: const Text('Log')),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      await widget.goalService!.logParentSave(goalId: g.id, amount: amount);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log save: $e')));
      }
    }
  }

  Future<void> _addMakeup(GoalProgressView g) async {
    final title = TextEditingController();
    final weight = TextEditingController(text: '10');
    final added = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a makeup chore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(
                  labelText: 'What needs doing?'),
            ),
            TextField(
              controller: weight,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Weight % (covers part of the gap)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context,
                  {'title': title.text, 'weight': double.tryParse(weight.text)}),
              child: const Text('Add')),
        ],
      ),
    );
    final t = added?['title'] as String?;
    final w = added?['weight'] as double?;
    if (t == null || t.isEmpty || w == null) return;
    try {
      await widget.goalService!.addMakeupChore(goalId: g.id, title: t, weightPct: w);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add chore: $e')));
      }
    }
  }
}
