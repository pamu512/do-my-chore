import 'package:flutter/material.dart';

import '../../services/album_service.dart';
import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../../services/queries.dart';
import 'album_screen.dart';
import 'approvals_screen.dart';
import 'new_goal_screen.dart';

/// Parent home: goals with ledger-derived progress, weeks-to-goal card,
/// pending approvals count, and the honesty banners.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key, this.goalService, this.choreService, this.albumService});

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
              'The ledger tracks what your kid earns — you settle real money '
              'offline. Photos in this demo are test data only.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.choreService != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.inbox),
                title: Text('$_pending chore${_pending == 1 ? '' : 's'} waiting for approval'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ApprovalsScreen(service: widget.choreService!)),
                ),
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
                      builder: (_) => NewGoalScreen(goalService: widget.goalService!)),
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
    final weeks = g.weeksLeft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(g.title, style: Theme.of(context).textTheme.titleMedium),
                Text('\$${g.goalBank.toStringAsFixed(0)} / \$${g.targetAmount.toStringAsFixed(0)}'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: g.progress, minHeight: 10),
            const SizedBox(height: 8),
            Text(weeks == null
                ? 'Add a weekly top-up to reach this goal on a schedule'
                : weeks == 0
                    ? 'Goal funded! 🎉'
                    : 'At \$${g.weeklyTopup.toStringAsFixed(0)}/week top-up + chores: about $weeks week${weeks == 1 ? '' : 's'} to go'),
            TextButton.icon(
              onPressed: widget.albumService == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AlbumScreen(
                                service: widget.albumService!, goalId: g.id)),
                      ),
              icon: const Icon(Icons.photo_album, size: 18),
              label: const Text('Goal Album'),
            ),
          ],
        ),
      ),
    );
  }
}
