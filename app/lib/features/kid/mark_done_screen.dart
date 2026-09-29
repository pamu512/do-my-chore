import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dmc_theme.dart';
import '../../services/chore_progress_math.dart';
import '../../services/chore_service.dart';
import '../../services/queries.dart';
import 'encouragement_widgets.dart';

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
    // DEMO_WALK: attach a tiny generated JPEG so the iOS Simulator walk
    // can submit photo chores without a working camera UI.
    if (const bool.fromEnvironment('DEMO_WALK')) {
      final f = File('${Directory.systemTemp.path}/demo_chore_photo.jpg');
      await f.writeAsBytes(_kDemoJpeg, flush: true);
      setState(() => _photoPath = f.path);
      return;
    }
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) setState(() => _photoPath = x.path);
  }

  /// Minimal valid JPEG (1x1 pixel) for DEMO_WALK photo submits.
  static const _kDemoJpeg = <int>[
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
    0x00, 0x00, 000, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
    0x7F, 0xFF, 0xD9,
  ];

  Future<void> _submit() async {
    if (widget.chore.requiresPhoto && _photoPath == null) return;
    setState(() => _submitting = true);
    try {
      if (widget.chore.requiresPhoto) {
        await widget.service.uploadAndSubmit(
          choreId: widget.chore.id,
          localPhotoPath: _photoPath!,
        );
      } else {
        await widget.service.submitChore(choreId: widget.chore.id);
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
                  Text('THIS CHORE IS WORTH', style: Dmc.micro),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
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
