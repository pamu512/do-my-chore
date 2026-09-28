import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/demo_auth.dart';
import '../models/role.dart';
import 'edge_ai_client.dart';
import 'jpeg_exif.dart';

/// Allowed submission status transitions. A rejected row is never flipped
/// back to pending — a retry always inserts a new submission row.
const Map<String, List<String>> kAllowedTransitions = {
  'pending': ['approved', 'rejected'],
};

/// A kid may only submit with a photo when the chore demands one — and a
/// photo chore without a photo is blocked client-side AND at submit time.
void assertSubmittable({required bool requiresPhoto, required bool hasPhoto}) {
  if (requiresPhoto && !hasPhoto) {
    throw ArgumentError('This chore needs a photo before you can mark it done');
  }
}

/// Short, kind nudge shown on the Kid Today card for a rejected chore.
String rejectNudge({required String choreTitle, String? parentNote}) {
  if (parentNote != null && parentNote.trim().isNotEmpty) {
    return parentNote.trim();
  }
  return 'So close! One more photo of the whole "$choreTitle" - bright light if you can - and this one\'s done.';
}

class ChoreService {
  ChoreService(this._clients);

  final RoleClients _clients;

  SupabaseClient get _parent => _clients.forRole(Role.parent);
  SupabaseClient get _kid => _clients.forRole(Role.kid);

  /// Read access for query extensions in `queries.dart`.
  SupabaseClient get parentClient => _parent;
  SupabaseClient get kidClient => _kid;

  /// Kid marks a chore done. Blocks photo-required chores without a photo.
  Future<void> submitChore({
    required String choreId,
    String? photoUrl,
    List<String>? alsoChoreIds,
  }) async {
    final chore = await _kid
        .from('chores')
        .select('requires_photo')
        .eq('id', choreId)
        .single();
    assertSubmittable(
      requiresPhoto: chore['requires_photo'] == true,
      hasPhoto: photoUrl != null,
    );
    final ids = <String>{choreId, ...?alsoChoreIds};
    await _kid.from('chore_submissions').insert([
      for (final id in ids)
        {
          'chore_id': id,
          'photo_url': ?photoUrl,
        },
    ]);
  }

  /// Kid uploads a chore photo to the family-prefixed storage path and
  /// submits. Photo chores without a photo are blocked (service rule).
  Future<String> uploadAndSubmit({
    required String choreId,
    required String localPhotoPath,
    List<String>? alsoChoreIds,
  }) async {
    final me = _kid.auth.currentUser?.id;
    final row = await _kid
        .from('profiles')
        .select('family_id')
        .eq('id', me!)
        .single();
    final familyId = row['family_id'] as String;
    final path = '$familyId/$choreId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final raw = await File(localPhotoPath).readAsBytes();
    final cleaned = stripJpegExif(raw);
    await _kid.storage.from('chore-photos').uploadBinary(
          path,
          cleaned,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    await submitChore(
      choreId: choreId,
      photoUrl: path,
      alsoChoreIds: alsoChoreIds,
    );
    return path;
  }

  /// Parent-side signed URL for a stored chore photo (private bucket).
  Future<String> photoUrl(String storagePath) {
    return _parent.storage
        .from('chore-photos')
        .createSignedUrl(storagePath, kChorePhotoSignedUrlTtlSeconds);
  }

  /// Advisory photo-assist for a pending card. Parent stays final.
  Future<PhotoAssistResult> assistPending({
    required String choreTitle,
    String? storagePath,
  }) async {
    String? b64;
    final path = storagePath;
    if (path != null && path.isNotEmpty) {
      try {
        final signed = await photoUrl(path);
        final client = HttpClient();
        try {
          final req = await client.getUrl(Uri.parse(signed));
          final res = await req.close().timeout(const Duration(seconds: 6));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
            // Never log image bytes or the base64 payload.
            if (bytes.isNotEmpty) b64 = base64Encode(bytes);
          }
        } finally {
          client.close(force: true);
        }
      } catch (_) {
        // ponytail: missing photo / storage → function abstains
      }
    }
    return invokePhotoAssist(
      _parent,
      choreTitle: choreTitle,
      imageBase64: b64,
    );
  }

  /// Parent approves: flips the submission to approved. Progress is derived
  /// from approved submissions x instance credits; no ledger writes here.
  Future<void> approveSubmission(String submissionId) async {
    await _parent.rpc('approve_chore_submission', params: {
      'p_submission_id': submissionId,
    });
  }

  /// Parent rejects with a nudge; the chore returns to Kid Today (rejected
  /// submissions are surfaced as retryable), and a retry inserts a new row.
  Future<void> rejectSubmission(String submissionId, String nudge) async {
    await rejectSubmissions([submissionId], nudge);
  }

  /// Send-back for a library cluster: one nudge on every pending row.
  Future<void> rejectSubmissions(List<String> submissionIds, String nudge) async {
    if (submissionIds.isEmpty) return;
    await _parent
        .from('chore_submissions')
        .update({
          'status': 'rejected',
          'reject_nudge': nudge,
          'decided_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', submissionIds);
  }
}
