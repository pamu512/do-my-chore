import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/album_service.dart';
import '../../services/chore_service.dart';
import '../../services/chore_progress_math.dart';
import '../../services/queries.dart';
import 'send_back_sheet.dart';

/// Parent approval inbox: AI photo assist suggests, the parent decides.
/// Cards show the percent credit this approval adds, never dollars.
/// Approving a photographed submission also files it into that goal's
/// Goal Album, so the album fills without any manual seeding.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({
    super.key,
    required this.service,
    this.albumService,
    this.weeksN,
  });

  final ChoreService service;

  /// Files approved photos into the Goal Album; null (no backend) skips it.
  final AlbumService? albumService;

  /// Weeks remaining on the goal, for the credit preview.
  final int? weeksN;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<PendingApproval> _pending = const [];
  final Map<String, String> _assist = {};
  bool _loading = true;
  String? _error;

  // Signed URLs for submitted photos, keyed by storage path.
  final Map<String, Future<String>> _photoFutures = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _photoFutures.clear();
    super.dispose();
  }

  Future<void> _refresh() async {
    List<PendingApproval> pending = const [];
    try {
      pending = collapsePendingByLibraryId(
        await widget.service.pendingForParent(),
      );
      if (mounted) {
        setState(() {
          _pending = pending;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load approvals. Pull to retry.';
        });
      }
      return;
    }
    for (final p in pending) {
      if (!p.requiresPhoto) continue;
      try {
        final assist = await widget.service.assistPending(
          choreTitle: p.choreTitle,
          storagePath: p.photoUrl,
        );
        if (!mounted) return;
        setState(() => _assist[p.submissionId] = assist.shownReason);
      } catch (_) {
        // ponytail: assist is advisory; the card still works
      }
    }
  }

  /// Marks a card as decided and animates it out before the list refresh.
  final Set<String> _decided = {};

  Future<void> _approve(PendingApproval p) async {
    for (final id in clusterSubmissionIds(p)) {
      _decided.add(id);
    }
    setState(() {});
    try {
      await widget.service.approveSubmission(p.submissionId);
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final id in clusterSubmissionIds(p)) {
            _decided.remove(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not approve: $e')));
      }
      return;
    }
    await _fileAlbumSeeds(p);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    await _refresh();
  }

  /// Approved photos file into the Goal Album. Runs only after the approve
  /// RPC succeeded, so nothing unapproved is ever filed. One failed insert
  /// must not drop the others: each seed is tried on its own.
  Future<void> _fileAlbumSeeds(PendingApproval p) async {
    final album = widget.albumService;
    if (album == null) return;
    final failures = <String>[];
    for (final seed in albumSeedsForApproval(p)) {
      try {
        await album.addToAlbum(
          goalId: seed.goalId,
          photoUrl: seed.photoUrl,
          submissionId: seed.submissionId,
          caption: seed.caption,
        );
      } catch (_) {
        failures.add(seed.submissionId);
      }
    }
    if (failures.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Approved, but ${failures.length} photo${failures.length == 1 ? '' : 's'} '
              'could not be added to the album.')));
    }
  }

  Future<void> _reject(PendingApproval p) async {
    final initial = rejectNudge(choreTitle: p.choreTitle);
    if (!mounted) return;
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SendBackSheet(
            kidName: 'Arjun',
            choreTitle: p.choreTitle,
            initialNote: initial,
            onCancel: () => Navigator.pop(ctx),
            onConfirm: (n) => Navigator.pop(ctx, n),
          ),
        );
      },
    );
    if (note == null || !mounted) return;
    final nudge = rejectNudge(choreTitle: p.choreTitle, parentNote: note);
    for (final id in clusterSubmissionIds(p)) {
      _decided.add(id);
    }
    setState(() {});
    try {
      await widget.service.rejectSubmissions(clusterSubmissionIds(p), nudge);
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final id in clusterSubmissionIds(p)) {
            _decided.remove(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send back: $e')));
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 420));
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sent back to Arjun with a note.'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ));
    }
  }

  String _creditPreview(PendingApproval p) {
    if (p.sharedGoalCount > 1) {
      return 'Credits ${p.sharedGoalCount} goals';
    }
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
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: const [
            DmcSkeleton(height: 220, radius: 12),
            SizedBox(height: 14),
            DmcSkeleton(height: 120, radius: 12),
          ],
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Approvals')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 30, color: Color(0xFF9AA39B)),
                const SizedBox(height: 10),
                Text('Couldn\'t load the inbox',
                    style:
                        Dmc.displayStyle(size: 18, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_error!,
                    style:
                        const TextStyle(fontSize: 13, color: Dmc.muted)),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _refresh();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            for (final p in _pending)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                opacity: _decided.contains(p.submissionId) ? 0 : 1,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  offset: _decided.contains(p.submissionId)
                      ? const Offset(0, -0.06)
                      : Offset.zero,
                  child: _card(p),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(PendingApproval p) {
    final photo = p.requiresPhoto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SUBMITTED BY ARJUN', style: Dmc.micro)
                .intoPadding(const EdgeInsets.fromLTRB(16, 14, 16, 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
              child: Text(p.choreTitle,
                  style:
                      Dmc.displayStyle(size: 21, weight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                '${_creditPreview(p)} · ${photo ? 'photo attached' : 'no photo needed'}',
                style: TextStyle(fontSize: 13.5, color: Dmc.muted),
              ),
            ),
            if (photo && p.photoUrl != null) ...[
              const SizedBox(height: 12),
              _PhotoFrame(
                urlFuture: _photoUrlFuture(p.photoUrl!),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
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
                            ? (_assist[p.submissionId] ??
                                'The photo check runs on Nebius Token Factory with Qwen3.8-27B. It is advisory only. You decide.')
                            : 'No photo needed - your word is final here.',
                        style: TextStyle(
                            fontSize: 13, height: 1.45, color: Dmc.ink2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _decided.contains(p.submissionId)
                          ? null
                          : () => _approve(p),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _decided.contains(p.submissionId)
                          ? null
                          : () => _reject(p),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Dmc.clayText,
                        side: const BorderSide(color: Color(0xFFE3C4BA)),
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Send back',
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _photoUrlFuture(String storagePath) {
    return _photoFutures.putIfAbsent(
        storagePath, () => widget.service.photoUrl(storagePath));
  }
}

extension _Pad on Widget {
  Widget intoPadding(EdgeInsetsGeometry p) => Padding(padding: p, child: this);
}

/// The submitted photo in a card-mounted frame: loads the signed URL,
/// shows a placeholder frame while loading and a note if it fails.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.urlFuture});

  final Future<String> urlFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: urlFuture,
      builder: (context, snap) {
        Widget image;
        if (snap.connectionState != ConnectionState.done) {
          image = const SizedBox(
            height: 170,
            child: Center(
                child: DmcSkeleton(height: 170, radius: 2)),
          );
        } else if (snap.hasError || snap.data == null) {
          image = Container(
            height: 110,
            color: Dmc.cream,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined, size: 16, color: Dmc.faint),
                  const SizedBox(width: 8),
                  Text('Photo couldn\'t load',
                      style: TextStyle(fontSize: 12.5, color: Dmc.muted)),
                ],
              ),
            ),
          );
        } else {
          image = Image.network(
            snap.data!,
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 110,
              color: Dmc.cream,
              child: Center(
                  child: Icon(Icons.image_outlined,
                      size: 22, color: Dmc.faint)),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Dmc.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Dmc.line),
              boxShadow: [
                BoxShadow(
                  color: Dmc.ink.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(2), child: image),
          ),
        );
      },
    );
  }
}
