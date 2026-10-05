import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../core/family_context.dart';
import '../../services/ai_service.dart';
import '../../services/cost_estimate.dart';
import '../../services/edge_ai_client.dart';
import '../../services/goal_service.dart';
import '../../services/ledger_math.dart';

/// Test stand-in for suggest-plan. Production leaves it null.
typedef NewGoalSuggestPlan = Future<SuggestPlanResult> Function({
  required String title,
  double? targetAmount,
  required DateTime targetDate,
  required int kidAge,
  required String goalMode,
});

/// Calendar day as UTC midnight, matching `DateTime.tryParse('yyyy-MM-dd')`.
DateTime _utcCalendarDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);

DateTime _defaultTargetDate() =>
    _utcCalendarDay(DateTime.now().add(const Duration(days: 98)));

/// Parent types a goal (amount optional), gets a combined estimate + chore
/// plan for the primary kid, can override the dollars, then Accept locks.
class NewGoalScreen extends StatefulWidget {
  const NewGoalScreen({
    super.key,
    required this.goalService,
    this.primaryKidAge = kPrimaryKidAge,
    @visibleForTesting this.suggestPlan,
  });

  final GoalService goalService;
  final int primaryKidAge;

  /// When set, Suggest calls this instead of the goal service.
  final NewGoalSuggestPlan? suggestPlan;

  @override
  State<NewGoalScreen> createState() => _NewGoalScreenState();
}

class _NewGoalScreenState extends State<NewGoalScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  DateTime _targetDate = _defaultTargetDate();
  String _mode = 'family_trip';
  bool _allowMakeup = false;

  SuggestPlanResult? _result;
  bool _loading = false;
  String? _error;

  int get _kidAge => widget.primaryKidAge;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final title = _title.text.isEmpty ? 'Disneyland' : _title.text;
      final typed = double.tryParse(_amount.text);
      final amount = (typed != null && typed > 0) ? typed : null;
      final date = _targetDate;
      final injected = widget.suggestPlan;
      final result = injected == null
          ? await widget.goalService.suggestPlan(
              title: title,
              targetAmount: amount,
              targetDate: date,
              kidAge: _kidAge,
              goalMode: _mode,
            )
          : await injected(
              title: title,
              targetAmount: amount,
              targetDate: date,
              kidAge: _kidAge,
              goalMode: _mode,
            );
      setState(() {
        _result = result;
        if (_amount.text.trim().isEmpty) {
          _amount.text = result.estimate.likely.toStringAsFixed(0);
        }
      });
    } catch (e) {
      setState(() => _error = 'Could not build plan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _lockedAmount() {
    final typed = double.tryParse(_amount.text);
    if (typed != null && typed > 0) return typed;
    final likely = _result?.estimate.likely;
    if (likely != null && likely > 0) return likely;
    return null;
  }

  Future<void> _accept() async {
    final result = _result;
    if (result == null) return;
    final locked = _lockedAmount();
    if (locked == null) {
      setState(() => _error = 'Add a cost or run Suggest first so we have a number to lock.');
      return;
    }
    try {
      final goalId = await widget.goalService.createGoal(
        title: _title.text.isEmpty ? 'Disneyland' : _title.text,
        cost: locked,
        goalMode: _mode,
        targetDate: _targetDate,
        allowMakeup: _allowMakeup,
      );
      await widget.goalService.acceptPlan(
        goalId: goalId,
        plan: result.plan,
        source: result.source,
      );
      if (!const bool.fromEnvironment('DEMO_WALK')) {
        final weeks = weeksUntil(_targetDate);
        await widget.goalService.lockGoalMoney(
          goalId: goalId,
          payload: lockPayload(
            estimate: result.estimate,
            lockedAmount: locked,
            weeks: weeks,
            deal: result.deals.isEmpty ? null : result.deals.first,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  String _shownDate(BuildContext context) {
    return MaterialLocalizations.of(context).formatMediumDate(
      DateTime(_targetDate.year, _targetDate.month, _targetDate.day),
    );
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = today.add(const Duration(days: 1));
    final lastDate = DateTime(today.year + 5, today.month, today.day);
    var initial =
        DateTime(_targetDate.year, _targetDate.month, _targetDate.day);
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Target date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _targetDate = DateTime.utc(picked.year, picked.month, picked.day);
    });
  }

  Widget _targetDateField(BuildContext context) {
    final shown = _shownDate(context);
    return Semantics(
      key: const Key('target-date-field'),
      button: true,
      container: true,
      label: 'Target date',
      value: shown,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: _pickTargetDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Target date',
              prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              shown,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _result?.plan;
    return Scaffold(
      appBar: AppBar(title: const Text('New Goal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Goal',
                hintText: 'e.g. Miami with the family for Christmas'),
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
                    labelText: 'Total cost (optional)',
                    hintText: 'leave blank to estimate',
                    prefixText: '\$'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _targetDateField(context)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Planning chores for the primary kid (age $_kidAge).',
            style: TextStyle(fontSize: 12.5, color: Dmc.muted),
          ),
          SwitchListTile(
            title: const Text('Allow makeup chores'),
            subtitle: const Text(
                'If your kid falls behind pace, you can add one-time catch-up chores. Off by default.'),
            value: _allowMakeup,
            onChanged: (v) => setState(() => _allowMakeup = v),
          ),
          const SizedBox(height: 8),
          Text(
            kAiPrivacyOneLiner,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Dmc.muted),
          ),
          const SizedBox(height: 12),
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
          if (_result != null && plan != null) ...[
            const SizedBox(height: 24),
            _estimateCard(_result!),
            const SizedBox(height: 12),
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
                      plan.why,
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
                                  text: ' - you fund the real cost, not kid pocket money',
                                  style: TextStyle(
                                      fontSize: 12.5, color: Dmc.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '\$${plan.weeklyParentSave.toStringAsFixed(0)}/wk',
                          style: Dmc.displayStyle(
                              size: 17, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...plan.chores.map(_planChoreRow),
                ],
              ),
            ),
            if (_result!.deals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('DEALS UNDER BUDGET', style: Dmc.micro),
              const SizedBox(height: 8),
              ..._result!.deals.map(_dealTile),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: Dmc.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Weights add up to ${plan.weightSum.toStringAsFixed(0)}%. '
                    'Over 100% means your kid can skip a few and still make it. '
                    'Change the cost above if you want a different lock amount.',
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

  Widget _estimateCard(SuggestPlanResult result) {
    final e = result.estimate;
    final live = e.provider != 'deterministic';
    final badge = live ? 'Live estimate (${e.provider})' : 'Offline estimate';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SAVE ESTIMATE', style: Dmc.micro),
            const SizedBox(height: 4),
            Text(
              badge,
              style: TextStyle(fontSize: 12.5, color: live ? Dmc.pine : Dmc.muted),
            ),
            const SizedBox(height: 8),
            Text(
              e.rationale,
              style: TextStyle(fontSize: 14, height: 1.5, color: Dmc.ink2),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _band('Low', e.low),
                const SizedBox(width: 8),
                _band('Likely', e.likely),
                const SizedBox(width: 8),
                _band('High', e.high),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'About \$${suggestedSavePerWeek(cost: e.likely, weeksN: result.weeks).toStringAsFixed(0)}/wk '
              'if you lock the likely number. You can type a different total above.',
              style: TextStyle(fontSize: 12.5, color: Dmc.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _band(String label, double amount) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Dmc.cream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Dmc.line),
        ),
        child: Column(
          children: [
            Text(label, style: Dmc.micro),
            const SizedBox(height: 4),
            Text(
              '\$${amount.toStringAsFixed(0)}',
              style: Dmc.displayStyle(size: 18, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealTile(GoalDeal deal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Dmc.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Dmc.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deal.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Dmc.ink,
              ),
            ),
            if (deal.price != null)
              Text(
                '\$${deal.price!.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 13, color: Dmc.pine),
              ),
            if (deal.snippet != null)
              Text(
                deal.snippet!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Dmc.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _planChoreRow(ChoreSpec c) {
    final plan = _result!.plan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Dmc.line)),
      ),
      child: Row(
        children: [
          Text(
            '${plan.chores.indexOf(c) + 1}'.padLeft(2, '0'),
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
