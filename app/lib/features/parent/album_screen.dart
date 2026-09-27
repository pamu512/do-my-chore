import 'package:flutter/material.dart';

import '../../services/album_service.dart';

/// Goal Album — photos from approved chores. Deletable. All demo/test data.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.service, required this.goalId});

  final AlbumService service;
  final String goalId;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<AlbumItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final items = await widget.service.itemsForGoal(widget.goalId);
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _delete(AlbumItem item) async {
    await widget.service.deleteAlbumItem(item.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goal Album')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text(
              'Demo photos only — test data, not real family photos. '
              'Parents can delete any item.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('No album photos yet'))
                    : GridView.count(
                        crossAxisCount: 2,
                        padding: const EdgeInsets.all(12),
                        children: _items
                            .map((item) => Card(
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(item.caption ?? 'Chore photo',
                                              textAlign: TextAlign.center),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                          tooltip: 'Delete from album',
                                          onPressed: () => _delete(item),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }
}
