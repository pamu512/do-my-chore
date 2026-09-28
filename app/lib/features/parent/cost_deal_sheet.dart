import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/cost_estimate.dart';
import '../../services/edge_ai_client.dart';
import '../../services/goal_service.dart';

/// Post-Accept parent sheet: show low/likely/high cost and optional deals,
/// then lock target_amount + weekly save. Kid % path is untouched.
class CostDealSheet extends StatefulWidget {
  const CostDealSheet({
    super.key,
    required this.goalService,
    required this.goalId,
    required this.title,
    required this.enteredCost,
    required this.goalMode,
    this.targetDate,
  });

  final GoalService goalService;
  final String goalId;
  final String title;
  final double enteredCost;
  final String goalMode;
  final DateTime? targetDate;

  @override
  State<CostDealSheet> createState() => _CostDealSheetState();
}

class _CostDealSheetState extends State<CostDealSheet> {
  CostOrchestrateResult? _result;
  bool _loading = true;
  bool _locking = false;
  String? _error;
  double? _selected;
  GoalDeal? _selectedDeal;

  int get _weeks {
    final d = widget.targetDate;
    if (d == null) return 12;
    final days = d.difference(DateTime.now()).inDays;
    return days < 7 ? 1 : (days / 7).ceil();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await invokeGoalCostOrchestrate(
      widget.goalService.parentClient,
      title: widget.title,
      targetAmount: widget.enteredCost,
      targetDate: widget.targetDate,
      goalMode: widget.goalMode,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _selected = result.estimate.likely;
      _loading = false;
    });
  }

  Future<void> _lock({required double amount, GoalDeal? deal, bool keepEntered = false}) async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _locking = true;
      _error = null;
    });
    try {
      if (!keepEntered) {
        await widget.goalService.lockGoalMoney(
          goalId: widget.goalId,
          payload: lockPayload(
            estimate: result.estimate,
            lockedAmount: amount,
            weeks: _weeks,
            deal: deal,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _locking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : _body(),
      ),
    );
  }

  Widget _body() {
    final result = _result!;
    final e = result.estimate;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('WHAT WILL THIS REALLY COST?', style: Dmc.micro),
          const SizedBox(height: 6),
          Text(
            widget.title,
            style: Dmc.displayStyle(size: 22, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            e.rationale,
            style: TextStyle(fontSize: 14, height: 1.5, color: Dmc.ink2),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _band('Low', e.low),
              const SizedBox(width: 8),
              _band('Likely', e.likely),
              const SizedBox(width: 8),
              _band('High', e.high),
            ],
          ),
          if (result.deals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('DEALS UNDER BUDGET', style: Dmc.micro),
            const SizedBox(height: 8),
            ...result.deals.map(_dealTile),
          ] else if (result.dealSearch == 'skipped') ...[
            const SizedBox(height: 12),
            Text(
              'Deal search is off until TAVILY_API_KEY is set. You can still lock a cost band.',
              style: TextStyle(fontSize: 12.5, color: Dmc.muted),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _locking
                ? null
                : () => _lock(
                      amount: _selected ?? e.likely,
                      deal: _selectedDeal,
                    ),
            child: Text(
              'Lock \$${(_selected ?? e.likely).toStringAsFixed(0)} and weekly save',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _locking
                ? null
                : () => _lock(
                      amount: widget.enteredCost,
                      keepEntered: true,
                    ),
            child: Text(
              'Keep my \$${widget.enteredCost.toStringAsFixed(0)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _band(String label, double amount) {
    final selected = _selected == amount && _selectedDeal == null;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selected = amount;
          _selectedDeal = null;
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Dmc.pineSoft : Dmc.cream,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Dmc.pine : Dmc.line),
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
      ),
    );
  }

  Widget _dealTile(GoalDeal deal) {
    final selected = identical(_selectedDeal, deal) ||
        (_selectedDeal != null &&
            _selectedDeal!.url == deal.url &&
            _selectedDeal!.title == deal.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() {
          _selectedDeal = deal;
          _selected = deal.price ?? _result!.estimate.likely;
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? Dmc.pineSoft : Dmc.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Dmc.pine : Dmc.line),
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
      ),
    );
  }
}
