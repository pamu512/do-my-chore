import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/chore_service.dart';
import '../../services/queries.dart';

/// Kid marks a chore done. Photo chores open the camera; submit is blocked
/// until a photo is attached.
class MarkDoneScreen extends StatefulWidget {
  const MarkDoneScreen({super.key, required this.service, required this.chore});

  final ChoreService service;
  final KidChoreCard chore;

  @override
  State<MarkDoneScreen> createState() => _MarkDoneScreenState();
}

class _MarkDoneScreenState extends State<MarkDoneScreen> {
  String? _photoPath;
  bool _submitting = false;

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
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x08, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
    0x7F, 0xFF, 0xD9,
  ];

  Future<void> _submit() async {
    if (widget.chore.requiresPhoto && _photoPath == null) return;
    setState(() => _submitting = true);
    try {
      await widget.service.uploadAndSubmit(
        choreId: widget.chore.id,
        localPhotoPath: _photoPath!,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chore = widget.chore;
    return Scaffold(
      appBar: AppBar(title: Text(chore.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (chore.nudge != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Parent said: ${chore.nudge}'),
              ),
            ),
          Text('\$${chore.reward.toStringAsFixed(2)} when approved'
              ' · ${chore.splitGoalPct}% goes to your goal'),
          const SizedBox(height: 16),
          if (chore.requiresPhoto) ...[
            Text('This one needs a photo so your parent can see it.'),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_camera),
              label: Text(_photoPath == null ? 'Take a photo' : 'Retake photo'),
            ),
            if (_photoPath != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Photo attached ✓'),
              ),
          ] else
            const Text('No photo needed for this one.'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_submitting || (chore.requiresPhoto && _photoPath == null))
                ? null
                : _submit,
            child: Text(_submitting ? 'Sending…' : 'Done! Send to parent'),
          ),
        ],
      ),
    );
  }
}
