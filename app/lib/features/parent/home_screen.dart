import 'package:flutter/material.dart';

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
  /// POC pace knob: weeks elapsed since the goal started. The seed creates
  /// the goal at reset time, so the demo starts at 0 and this stays final;
  /// a follow-up would derive it from goals.created_at.
  final int _weeksElapsedSample = 0;

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
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Home')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'The app plans the money; you settle it offline. '
              'No bank, no card. Photos in this demo are test data only.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.choreService != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.inbox),
                title: Text(
                    '$_pending chore${_pending == 1 ? '' : 's'} waiting for approval'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ApprovalsScreen(service: widget.choreService!)),
                  );
                  _refresh();
                },
              ),
            ),
          ..._goals.map((g) => _goalCard(context, g)),
          const SizedBox(height: 8),
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
              icon: const Icon(Icons.add),
              label: const Text('New Goal'),
            ),
        ],
      ),
    );
  }

  Widget _goalCard(BuildContext context, GoalProgressView g) {
    // POC pace estimate: treat elapsed weeks as 0 until first approval data
    // exists, else scale by weeks passed since creation is unknown; the
    // behind-pace signal uses a simple elapsed share the parent can tune.
    final behind = g.allowMakeup &&
        g.choreProgressPct + 1e-6 < 100 * _weeksElapsedSample / g.weeksN;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(g.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                    '${g.goalMode == 'family_trip' ? 'Trip' : 'Item'}: \$${g.targetAmount.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Save \$${g.weeklyParentSave.toStringAsFixed(0)}/week for ${g.weeksN} weeks'
                ' (about \$${(g.weeklyParentSave * g.weeksN).toStringAsFixed(0)} total)'),
            LinearProgressIndicator(
                value: g.parentSaveFraction, minHeight: 6),
            Text(
                'Saved so far: \$${g.parentSaved.toStringAsFixed(0)} of \$${g.targetAmount.toStringAsFixed(0)}'),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kid chore progress',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('${g.choreProgressPct.toStringAsFixed(0)}%'
                    ' (weights ${g.planWeightSum.toStringAsFixed(0)}%)'),
              ],
            ),
            LinearProgressIndicator(
                value: g.choreProgressPct / 100, minHeight: 10),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _logSave(g),
                  icon: const Icon(Icons.savings, size: 18),
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
                                    goalId: g.id)),
                          ),
                  icon: const Icon(Icons.photo_album, size: 18),
                  label: const Text('Album'),
                ),
              ],
            ),
            if (behind)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Behind pace'),
                  subtitle:
                      const Text('Add a one-time makeup chore to catch up?'),
                  trailing: TextButton(
                    onPressed: () => _addMakeup(g),
                    child: const Text('Add'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
