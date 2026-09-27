import 'package:flutter/material.dart';

import '../../services/ai_service.dart';
import '../../services/goal_service.dart';

/// Parent creates a goal (type, cost, date, makeup switch), gets an
/// AI-suggested plan (parent weekly save + kid habit weights with a plain
/// language why), edits it, and accepts - which writes the chores.
class NewGoalScreen extends StatefulWidget {
  const NewGoalScreen({super.key, required this.goalService});

  final GoalService goalService;

  @override
  State<NewGoalScreen> createState() => _NewGoalScreenState();
}

class _NewGoalScreenState extends State<NewGoalScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController(text: '3500');
  final _date = TextEditingController(
      text: DateTime.now().add(const Duration(days: 98)).toIso8601String().substring(0, 10));
  final _age = TextEditingController(text: '9');
  String _mode = 'family_trip';
  bool _allowMakeup = false;

  AiPlanSuggestion? _plan;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _date.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Deterministic builder is the in-app path and what the edge function
      // falls back to without an API key.
      final plan = buildDeterministicPlan(
        title: _title.text.isEmpty ? 'Disneyland' : _title.text,
        targetAmount: double.tryParse(_amount.text) ?? 3500,
        weeks: weeksUntil(DateTime.parse(_date.text)),
        kidAge: int.tryParse(_age.text) ?? 8,
      );
      setState(() => _plan = plan);
    } catch (e) {
      setState(() => _error = 'Could not build plan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    final plan = _plan;
    if (plan == null) return;
    try {
      final goalId = await widget.goalService.createGoal(
        title: _title.text.isEmpty ? 'Disneyland' : _title.text,
        cost: double.tryParse(_amount.text) ?? 3500,
        goalMode: _mode,
        targetDate: DateTime.tryParse(_date.text),
        allowMakeup: _allowMakeup,
      );
      await widget.goalService.acceptPlan(goalId: goalId, plan: plan);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Goal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Goal (e.g. Disneyland)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'family_trip', label: Text('Family trip')),
              ButtonSegment(value: 'kid_item', label: Text('Kid item')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Total cost (\$)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _date,
                decoration: const InputDecoration(
                    labelText: 'Target date', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Allow makeup chores'),
            subtitle: const Text(
                'If your kid falls behind pace, you can add one-time catch-up chores. Off by default.'),
            value: _allowMakeup,
            onChanged: (v) => setState(() => _allowMakeup = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Kid age', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _suggest,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Suggest plan'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child:
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_plan != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Why this plan',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_plan!.why),
                    const Divider(height: 24),
                    Text(
                        'You save: \$${_plan!.weeklyParentSave.toStringAsFixed(2)}/week until the date'),
                    const SizedBox(height: 8),
                    ..._plan!.chores.map((c) => ListTile(
                          dense: true,
                          leading: Icon(
                              c.requiresPhoto ? Icons.photo_camera : Icons.task_alt,
                              size: 20),
                          title: Text(c.title),
                          subtitle: Text(
                              '${_cadenceLabel(c.cadence)} · weight ${c.weightPct.toStringAsFixed(0)}%'),
                        )),
                    const Divider(height: 24),
                    Text(
                        'Weights add up to ${_plan!.weightSum.toStringAsFixed(0)}%. '
                        'Over 100% means your kid can skip a few and still make it.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _accept,
              child: const Text('Accept plan'),
            ),
          ],
        ],
      ),
    );
  }

  String _cadenceLabel(String cadence) {
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
