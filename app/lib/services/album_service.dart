import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_auth.dart';
import '../models/role.dart';

class AlbumItem {
  final String id;
  final String goalId;
  final String photoUrl;
  final String? caption;

  const AlbumItem({
    required this.id,
    required this.goalId,
    required this.photoUrl,
    this.caption,
  });
}

/// Goal Album: photos from approved submissions, deletable by the parent.
/// All photos are demo/test data only. See the privacy copy in the album UI.
class AlbumService {
  AlbumService(this._clients);

  final RoleClients _clients;

  SupabaseClient get _parent => _clients.forRole(Role.parent);

  Future<List<AlbumItem>> itemsForGoal(String goalId) async {
    final rows = await _parent
        .from('album_items')
        .select('id, goal_id, photo_url, caption')
        .eq('goal_id', goalId)
        .order('created_at', ascending: false);
    return rows
        .map<AlbumItem>((r) => AlbumItem(
              id: r['id'] as String,
              goalId: r['goal_id'] as String,
              photoUrl: r['photo_url'] as String,
              caption: r['caption'] as String?,
            ))
        .toList();
  }

  Future<void> addToAlbum({
    required String goalId,
    required String photoUrl,
    String? submissionId,
    String? caption,
  }) async {
    await _parent.from('album_items').insert({
      'goal_id': goalId,
      'photo_url': photoUrl,
      'chore_submission_id': ?submissionId,
      'caption': ?caption,
    });
  }

  Future<void> deleteAlbumItem(String itemId) async {
    await _parent.from('album_items').delete().eq('id', itemId);
  }
}
