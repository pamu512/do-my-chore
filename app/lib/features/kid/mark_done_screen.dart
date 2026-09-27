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
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x != null) setState(() => _photoPath = x.path);
  }

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
