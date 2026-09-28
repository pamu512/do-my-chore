import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/ai_service.dart';
import '../../services/edge_ai_client.dart';
import '../../services/goal_service.dart';
import 'cost_deal_sheet.dart';

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
      // Prefer the edge function when it is deployed; the local builder is
      // the offline / Basics path and what the function itself falls back to.
      final title = _title.text.isEmpty ? 'Disneyland' : _title.text;
      final amount = double.tryParse(_amount.text) ?? 3500;
      final date = DateTime.tryParse(_date.text) ??
          DateTime.now().add(const Duration(days: 98));
      final plan = await widget.goalService.suggestPlan(
        title: title,
        targetAmount: amount,
        targetDate: date,
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
      if (!mounted) return;
      // DEMO_WALK / Basics video: Accept still returns home. The cost sheet
      // is the Nebius eligibility path and must not block that beat.
      if (!const bool.fromEnvironment('DEMO_WALK')) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => CostDealSheet(
            goalService: widget.goalService,
            goalId: goalId,
            title: _title.text.isEmpty ? 'Disneyland' : _title.text,
            enteredCost: double.tryParse(_amount.text) ?? 3500,
            goalMode: _mode,
            targetDate: DateTime.tryParse(_date.text),
          ),
        );
      }
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Goal name', hintText: 'e.g. Disneyland'),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            style: ButtonStyle(
              side: WidgetStatePropertyAll(
                  BorderSide(color: Dmc.lineStrong)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
            segments: const [
              ButtonSegment(value: 'family_trip', label: Text('Family trip')),
              ButtonSegment(value: 'kid_item', label: Text('Kid item')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Total cost (\$)', prefixText: '\$'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _date,
                decoration: const InputDecoration(
                    labelText: 'Target date',
                    prefixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Allow makeup chores'),
            subtitle: const Text(
                'If your kid falls behind pace, you can add one-time catch-up chores. Off by default.'),
            value: _allowMakeup,
            onChanged: (v) => setState(() => _allowMakeup = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kid age', suffixText: 'years'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _suggest,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Suggest plan'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_plan != null) ...[
            const SizedBox(height: 24),
            Card(
              color: Dmc.cream,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WHY THIS PLAN', style: Dmc.micro),
                    const SizedBox(height: 6),
                    Text(
                      _plan!.why,
                      style: TextStyle(
                          fontSize: 14, height: 1.55, color: Dmc.ink2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('THE PLAN', style: Dmc.micro),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Dmc.pineSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.calendar_today_outlined,
                              size: 18, color: Dmc.pine),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: 'Weekly top-up',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Dmc.ink),
                              children: [
                                TextSpan(
                                  text: ' - from you, every week',
                                  style: TextStyle(
                                      fontSize: 12.5, color: Dmc.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '\$${_plan!.weeklyParentSave.toStringAsFixed(0)}/wk',
                          style: Dmc.displayStyle(
                              size: 17, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ..._plan!.chores.map(_planChoreRow),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: Dmc.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Weights add up to ${_plan!.weightSum.toStringAsFixed(0)}%. '
                    'Over 100% means your kid can skip a few and still make it.',
                    style: TextStyle(fontSize: 12.5, color: Dmc.muted),
                  ),
                ),
              ],
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

  Widget _planChoreRow(ChoreSpec c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Dmc.line)),
      ),
      child: Row(
        children: [
          Text(
            '${_plan!.chores.indexOf(c) + 1}'.padLeft(2, '0'),
            style: TextStyle(fontSize: 12, color: Dmc.faint),
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
                            fontWeight: FontWeight.w500,
                            color: Dmc.ink),
                      ),
                    ),
                    if (c.requiresPhoto) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.photo_camera_outlined,
                          size: 15, color: Dmc.faint),
                    ],
                  ],
                ),
                Text(
                  '${_cadenceLabel(c.cadence)} · ${c.weightPct.toStringAsFixed(0)}% weight',
                  style: TextStyle(fontSize: 12.5, color: Dmc.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Dmc.cream,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Dmc.line),
            ),
            child: Text(
              '${c.weightPct.toStringAsFixed(0)}%',
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
