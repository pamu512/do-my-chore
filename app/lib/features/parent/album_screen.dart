import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';
import '../../services/album_service.dart';
import '../../services/chore_service.dart';

/// Goal Album - photos from approved chores. Deletable, with a moment of
/// undo before the delete sticks. All demo/test data.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    required this.service,
    required this.goalId,
    this.choreService,
  });

  final AlbumService service;
  final String goalId;

  /// For signing photo URLs from the private bucket.
  final ChoreService? choreService;

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
    // Optimistic remove + undo window. The server delete only fires if the
    // snackbar closes without an undo, so Undo genuinely cancels.
    final oldItems = List<AlbumItem>.of(_items);
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: const Text('Removed from the album.'),
      duration: const Duration(milliseconds: 3500),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          undone = true;
          setState(() => _items = oldItems);
        },
      ),
    ));
    // The snackbar owns the 3.5s window; delete only if not undone.
    await Future<void>.delayed(const Duration(milliseconds: 3700));
    if (undone) return;
    try {
      await widget.service.deleteAlbumItem(item.id);
    } catch (_) {
      // Next refresh re-syncs; album is demo data.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goal Album')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(
                    child: GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.86,
                      children: List.generate(
                          4,
                          (i) => const DmcSkeleton(
                              radius: 4, height: 200)),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_outlined,
                                size: 30, color: Dmc.faint),
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
                                    child: _AlbumPhoto(
                                      item: item,
                                      choreService: widget.choreService,
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

/// Renders an album photo. Storage paths (no scheme) are signed via the
/// chore service; full http(s) URLs load directly.
class _AlbumPhoto extends StatefulWidget {
  const _AlbumPhoto({required this.item, this.choreService});

  final AlbumItem item;
  final ChoreService? choreService;

  @override
  State<_AlbumPhoto> createState() => _AlbumPhotoState();
}

class _AlbumPhotoState extends State<_AlbumPhoto> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    final url = widget.item.photoUrl;
    if (url.startsWith('http')) {
      _url = Future.value(url);
    } else if (widget.choreService != null) {
      _url = widget.choreService!.photoUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) {
      return _placeholder();
    }
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEBE1),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }
        if (snap.hasError) return _placeholder();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(7),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
          child: Image.network(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Dmc.marigoldSoft,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Dmc.lineStrong),
      ),
      child: Icon(Icons.image_outlined, size: 26, color: Dmc.faint),
    );
  }
}
