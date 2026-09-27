import 'package:flutter/material.dart';

import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../../services/queries.dart';
import 'mark_done_screen.dart';

/// Kid Today: chores (with rejected-nudge retries) + goal vs pocket progress.
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
        padding: const EdgeInsets.all(16),
        children: [
          ..._goals.map((g) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(g.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '\$${g.goalBank.toStringAsFixed(0)} / \$${g.targetAmount.toStringAsFixed(0)}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: g.progress, minHeight: 10),
                      const SizedBox(height: 8),
                      Text('Pocket: \$${g.pocket.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
          ..._chores.map((c) => Card(
                child: ListTile(
                  leading: Icon(c.requiresPhoto ? Icons.photo_camera : Icons.task_alt),
                  title: Text(c.title),
                  subtitle: c.nudge != null
                      ? Text('↻ Try again — ${c.nudge}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))
                      : Text(
                          '\$${c.reward.toStringAsFixed(2)} · ${c.splitGoalPct}% to goal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (widget.choreService == null) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MarkDoneScreen(
                              service: widget.choreService!, chore: c)),
                    );
                    _refresh();
                  },
                ),
              )),
        ],
      ),
    );
  }
}
