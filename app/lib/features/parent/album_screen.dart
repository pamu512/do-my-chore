import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/album_service.dart';

/// Goal Album - photos from approved chores. Deletable. All demo/test data.
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_outlined,
                                size: 30, color: const Color(0xFF9AA39B)),
                            const SizedBox(height: 10),
                            Text('No photos in the album yet.',
                                style: Dmc.displayStyle(
                                    size: 18, weight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Approved chores with photos land here.',
                                style:
                                    TextStyle(fontSize: 13, color: Dmc.muted)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.86,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          final tilt = i.isOdd ? 0.025 : -0.028;
                          return Transform.rotate(
                            angle: tilt,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Dmc.line),
                                boxShadow: [
                                  BoxShadow(
                                    color: Dmc.ink.withValues(alpha: 0.10),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: Dmc.marigoldSoft,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                            color: Dmc.lineStrong),
                                      ),
                                      child: Icon(Icons.image_outlined,
                                          size: 26, color: Dmc.faint),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 0, 4, 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.caption ?? 'Chore photo',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Dmc.ink,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            iconSize: 16,
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            tooltip: 'Delete from album',
                                            onPressed: () => _delete(item),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: Dmc.cream,
              border: Border(top: BorderSide(color: Dmc.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.image_outlined, size: 15, color: Dmc.faint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Demo photos only - test data, not real family photos. '
                    'Parents can delete any item.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.45, color: Dmc.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
