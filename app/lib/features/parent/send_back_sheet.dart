import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/chore_service.dart';

/// Parent bottom sheet: edit the note and see exactly what the kid will read.
class SendBackSheet extends StatefulWidget {
  const SendBackSheet({
    super.key,
    required this.kidName,
    required this.choreTitle,
    required this.initialNote,
    required this.onCancel,
    required this.onConfirm,
  });

  final String kidName;
  final String choreTitle;
  final String initialNote;
  final VoidCallback onCancel;
  final ValueChanged<String> onConfirm;

  @override
  State<SendBackSheet> createState() => _SendBackSheetState();
}

class _SendBackSheetState extends State<SendBackSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _preview => _controller.text.trim().isEmpty
      ? widget.initialNote
      : _controller.text.trim();

  void _send() {
    widget.onConfirm(
      rejectNudge(choreTitle: widget.choreTitle, parentNote: _controller.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Send back with a note',
              style: Dmc.displayStyle(size: 19, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            '${widget.kidName} sees this as a friendly next try - never a rejection on his screen.',
            style: const TextStyle(fontSize: 12.5, color: Dmc.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Dmc.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: Dmc.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Dmc.lineStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Dmc.lineStrong),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Dmc.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Dmc.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.kidName} will see',
                    style: Dmc.micro.copyWith(color: Dmc.marigoldDeep)),
                const SizedBox(height: 6),
                Text('A note from your parent',
                    style: Dmc.micro.copyWith(color: Dmc.marigoldDeep)),
                const SizedBox(height: 4),
                Text(
                  _preview,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF5C3F11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Dmc.ink2,
                    side: const BorderSide(color: Dmc.lineStrong),
                  ),
                  child: const Text('Keep it'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                child: FilledButton(
                  onPressed: _send,
                  child: const Text('Send note'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
