import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dmc_theme.dart';
import '../../services/chore_progress_math.dart';
import '../../services/chore_service.dart';
import '../../services/queries.dart';
import 'encouragement_widgets.dart';

/// Bundled DEMO_WALK photo. Fold/laundry, else tidy/bed/room, else dishes
/// (wash/dishes and any other title).
String demoWalkPhotoAsset(String title) {
  final t = title.toLowerCase();
  if (t.contains('fold') || t.contains('laundry')) {
    return 'assets/photos/laundry.jpg';
  }
  if (t.contains('tidy') || t.contains('bed') || t.contains('room')) {
    return 'assets/photos/bed.jpg';
  }
  return 'assets/photos/dishes.jpg';
}

/// Kid marks a chore done. Photo chores open the camera; submit is blocked
/// until a photo is attached. Copy is percent-based only.
class MarkDoneScreen extends StatefulWidget {
  const MarkDoneScreen({
    super.key,
    required this.service,
    required this.chore,
    this.weeksN,
  });

  final ChoreService service;
  final KidChoreCard chore;

  /// Weeks remaining on the goal, for the per-approval credit preview.
  final int? weeksN;

  @override
  State<MarkDoneScreen> createState() => _MarkDoneScreenState();
}

class _MarkDoneScreenState extends State<MarkDoneScreen> {
  String? _photoPath;
  bool _submitting = false;
  bool _sent = false;

  Future<void> _pickPhoto() async {
    // DEMO_WALK: camera stub only. The bundled photo still goes to live photo-assist.
    if (const bool.fromEnvironment('DEMO_WALK')) {
      try {
        final data = await rootBundle.load(demoWalkPhotoAsset(widget.chore.title));
        final f = File('${Directory.systemTemp.path}/demo_chore_photo.jpg');
        await f.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        if (!mounted) return;
        setState(() => _photoPath = f.path);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach the demo photo: $e')),
        );
      }
      return;
    }
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) setState(() => _photoPath = x.path);
  }

  Future<void> _submit() async {
    if (widget.chore.requiresPhoto && _photoPath == null) return;
    setState(() => _submitting = true);
    try {
      final also = submissionChoreIds(widget.chore);
      if (widget.chore.requiresPhoto) {
        await widget.service.uploadAndSubmit(
          choreId: widget.chore.id,
          localPhotoPath: _photoPath!,
          alsoChoreIds: also,
        );
      } else {
        await widget.service.submitChore(
          choreId: widget.chore.id,
          alsoChoreIds: also,
        );
      }
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Per-approval credit preview: weight / expected instances.
  String _creditLine() {
    final c = widget.chore;
    if (c.sharedGoalCount > 1) {
      return 'counts for ${c.sharedGoalCount} goals';
    }
    if (widget.weeksN == null) return 'Adds to your goal progress';
    final expected =
        expectedInstances(cadence: c.cadence, weeksN: widget.weeksN!);
    final credit =
        instanceCreditPct(weightPct: c.weightPct, expectedInstances: expected);
    return 'each check-in adds +${credit.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    return MarkDoneView(
      chore: widget.chore,
      weeksN: widget.weeksN,
      sent: _sent,
      submitting: _submitting,
      photoPath: _photoPath,
      creditLine: _creditLine(),
      onPickPhoto: _pickPhoto,
      onSubmit: _submit,
      onBack: () => Navigator.pop(context),
    );
  }
}

/// Presentational Mark Done (form or after-send). Tests pump this without
/// constructing a [ChoreService].
class MarkDoneView extends StatelessWidget {
  const MarkDoneView({
    super.key,
    required this.chore,
    required this.sent,
    required this.submitting,
    required this.onSubmit,
    required this.onBack,
    this.weeksN,
    this.photoPath,
    this.creditLine,
    this.onPickPhoto,
  });

  final KidChoreCard chore;
  final int? weeksN;
  final bool sent;
  final bool submitting;
  final String? photoPath;
  final String? creditLine;
  final VoidCallback? onPickPhoto;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(chore.title)),
      body: sent
          ? KidSentConfirmation(onBack: onBack)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (chore.nudge != null) ...[
                  KidNextTryNote(note: chore.nudge!),
                  const SizedBox(height: 4),
                ],
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chore.sharedGoalCount > 1
                        ? 'THIS HABIT COUNTS FOR'
                        : 'THIS CHORE IS WORTH',
                    style: Dmc.micro,
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    chore.sharedGoalCount > 1
                        ? TextSpan(
                            text: '${chore.sharedGoalCount} goals',
                            style: Dmc.displayStyle(
                                size: 28,
                                weight: FontWeight.w700,
                                color: Dmc.marigoldDeep),
                          )
                        : TextSpan(
                            text: '+${chore.weightPct.toStringAsFixed(0)}%',
                            style: Dmc.displayStyle(
                                size: 28,
                                weight: FontWeight.w700,
                                color: Dmc.marigoldDeep),
                            children: [
                              TextSpan(
                                text: ' of the goal',
                                style: TextStyle(
                                  fontFamily: Dmc.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Dmc.muted,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${chore.cadenceLabel} chore · ${creditLine ?? 'Adds to your goal progress'}',
                    style: TextStyle(fontSize: 13, height: 1.45, color: Dmc.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (chore.requiresPhoto) ...[
            Text('This one needs a photo so your parent can see it.',
                style: TextStyle(fontSize: 13, color: Dmc.muted)),
            const SizedBox(height: 8),
            if (photoPath != null)
              // The actual captured photo, framed like a snapshot.
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.file(
                    File(photoPath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 180,
                      color: Dmc.marigoldSoft,
                      child: const Icon(Icons.image_outlined,
                          size: 30, color: Dmc.faint),
                    ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: onPickPhoto,
              style: OutlinedButton.styleFrom(
                backgroundColor: Dmc.surface,
                foregroundColor: Dmc.ink,
                side: const BorderSide(color: Dmc.lineStrong),
              ),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(photoPath == null ? 'Take a photo' : 'Retake photo'),
            ),
            if (photoPath != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: Dmc.pineSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDFE8E2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: Dmc.pine),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Photo attached - it counts once your parent takes a look.',
                        style: TextStyle(fontSize: 13.5, color: Dmc.pineDeep),
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Dmc.pineSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDFE8E2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check, size: 18, color: Dmc.pine),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'No photo needed for this one - just tap below when it\'s done.',
                      style: TextStyle(fontSize: 13.5, color: Dmc.pineDeep),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (submitting || (chore.requiresPhoto && photoPath == null))
                ? null
                : onSubmit,
            child: Text(submitting ? 'Sending...' : 'Done! Send to parent'),
          ),
        ],
      ),
    );
  }
}
