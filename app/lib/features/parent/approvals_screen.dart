import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
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
    return '+${credit.toStringAsFixed(1)}% to goal';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Approvals')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_pending.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Approvals')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 30, color: const Color(0xFF9AA39B)),
              const SizedBox(height: 10),
              Text('Nothing waiting.',
                  style: Dmc.displayStyle(size: 18, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text("You're all caught up.",
                  style: TextStyle(fontSize: 13, color: Dmc.muted)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: _pending.map((p) {
        final photo = p.requiresPhoto;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SUBMITTED BY ARJUN', style: Dmc.micro),
                const SizedBox(height: 3),
                Text(p.choreTitle,
                    style:
                        Dmc.displayStyle(size: 21, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${_creditPreview(p)} · ${photo ? 'photo attached' : 'no photo needed'}',
                  style: TextStyle(fontSize: 13.5, color: Dmc.muted),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: Dmc.cream,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Dmc.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.auto_awesome, size: 15, color: Dmc.faint),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          photo
                              ? 'AI assist is advisory only. The photo check-in is a habit cue, not a payroll audit - you decide.'
                              : 'No photo needed for this one - your call is the final word.',
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: Dmc.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _approve(p),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reject(p),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Dmc.clayText,
                          side: const BorderSide(color: Color(0xFFE3C4BA)),
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject with nudge',
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
      ),
    );
  }
}
