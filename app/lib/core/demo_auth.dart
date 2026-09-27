import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/role.dart';
import 'supabase_config.dart';

/// Two ready Supabase clients — one signed in as the demo parent, one as the
/// demo kid. Switching roles never re-authenticates, and every data call runs
/// under the active role's JWT, so RLS is always enforced by the backend.
class RoleClients {
  RoleClients({required this.parent, required this.kid});

  final SupabaseClient parent;
  final SupabaseClient kid;

  SupabaseClient forRole(Role role) =>
      role == Role.parent ? parent : kid;

  Future<void> dispose() async {
    await parent.dispose();
    await kid.dispose();
  }
}

class DemoAuth {
  /// Signs in both demo accounts. Passwords are seeded demo-only credentials
  /// for a local Supabase instance (see README honesty notices).
  static Future<RoleClients> connect(SupabaseConfig config) async {
    final parentClient = SupabaseClient(config.url, config.anonKey);
    final kidClient = SupabaseClient(config.url, config.anonKey);

    final parentRes = await parentClient.auth
        .signInWithPassword(email: 'parent@demo', password: 'demo1234');
    if (parentRes.session == null) {
      await parentClient.dispose();
      await kidClient.dispose();
      throw StateError('parent@demo sign-in failed');
    }

    final kidRes = await kidClient.auth
        .signInWithPassword(email: 'kid@demo', password: 'demo1234');
    if (kidRes.session == null) {
      await parentClient.dispose();
      await kidClient.dispose();
      throw StateError('kid@demo sign-in failed');
    }

    return RoleClients(parent: parentClient, kid: kidClient);
  }
}
