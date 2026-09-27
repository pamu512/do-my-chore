import 'package:flutter/material.dart';

import '../../core/demo_auth.dart';
import '../../models/role.dart';
import '../../services/album_service.dart';
import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../kid/today_screen.dart';
import '../parent/home_screen.dart';
import 'role_scope.dart';

/// App shell with the in-app Parent ↔ Kid role switch. Two pre-authenticated
/// clients mean switching never re-authenticates — the demo video depends on
/// it — and every call runs under the active role's JWT so RLS always applies.
class RoleSwitchShell extends StatefulWidget {
  const RoleSwitchShell({super.key, this.scope, this.clients});

  /// Optional injected scope (widget tests); a fresh one is created if null.
  final RoleScope? scope;

  /// Pre-authenticated clients; null renders the no-backend demo mode.
  final RoleClients? clients;

  @override
  State<RoleSwitchShell> createState() => _RoleSwitchShellState();
}

class _RoleSwitchShellState extends State<RoleSwitchShell> {
  RoleScope? _ownScope;

  RoleScope get scope => widget.scope ?? (_ownScope ??= RoleScope());

  @override
  void dispose() {
    _ownScope?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scope,
      builder: (context, _) {
        final role = scope.role;
        final clients = widget.clients;

        Widget body;
        if (clients == null) {
          body = role == Role.parent
              ? const ParentHomeScreen()
              : const KidTodayScreen();
        } else {
          final goalService = GoalService(clients);
          final choreService = ChoreService(clients);
          body = role == Role.parent
              ? ParentHomeScreen(
                  goalService: goalService,
                  choreService: choreService,
                  albumService: AlbumService(clients),
                )
              : KidTodayScreen(
                  goalService: goalService,
                  choreService: choreService,
                );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Do My Chore'),
            actions: [
              SegmentedButton<Role>(
                segments: const [
                  ButtonSegment(value: Role.parent, label: Text('Parent')),
                  ButtonSegment(value: Role.kid, label: Text('Kid')),
                ],
                selected: {role},
                onSelectionChanged: (s) => scope.role = s.first,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
