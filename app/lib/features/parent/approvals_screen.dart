import 'package:flutter/material.dart';

import '../../services/chore_service.dart';
import '../../services/chore_progress_math.dart';
import '../../services/queries.dart';

/// Parent approval inbox: AI photo assist suggests, the parent decides.
/// Cards show the percent credit this approval adds, never dollars.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, required this.service, this.weeksN});

  final ChoreService service;

  /// Weeks remaining on the goal, for the credit preview.
  final int? weeksN;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<PendingApproval> _pending = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pending = await widget.service.pendingForParent();
    if (mounted) {
      setState(() {
        _pending = pending;
        _loading = false;
      });
    }
  }

  Future<void> _approve(PendingApproval p) async {
    await widget.service.approveSubmission(p.submissionId);
    await _refresh();
  }

  Future<void> _reject(PendingApproval p) async {
    final nudge = rejectNudge(choreTitle: p.choreTitle);
    await widget.service.rejectSubmission(p.submissionId, nudge);
    await _refresh();
  }

  String _creditPreview(PendingApproval p) {
    if (widget.weeksN == null) return '+credit';
    final expected =
        expectedInstances(cadence: p.cadence, weeksN: widget.weeksN!);
    final credit =
        instanceCreditPct(weightPct: p.weightPct, expectedInstances: expected);
    return '+${credit.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pending.isEmpty) {
      return const Center(child: Text('Nothing waiting for approval'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _pending
          .map((p) => Card(
                child: ListTile(
                  title: Text(p.choreTitle),
                  subtitle: Text(
                      '${_creditPreview(p)} · ${p.requiresPhoto ? "photo attached" : "no photo needed"}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _approve(p),
                      ),
                      IconButton(
                        tooltip: 'Reject with nudge',
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _reject(p),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
