import 'package:flutter/material.dart';

import '../../models/role.dart';
import '../kid/today_screen.dart';
import '../parent/home_screen.dart';
import 'role_scope.dart';

/// App shell with the in-app Parent ↔ Kid role switch. One session, no
/// re-auth — the demo video depends on instant switching.
class RoleSwitchShell extends StatefulWidget {
  const RoleSwitchShell({super.key, this.scope, this.clients});

  /// Optional injected scope (widget tests); a fresh one is created if null.
  final RoleScope? scope;

  /// Optional pre-authenticated clients; when null the shell renders in
  /// "backend not connected" demo mode (UI only, no data calls).
  final dynamic clients;

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
          body: role == Role.parent
              ? const ParentHomeScreen()
              : const KidTodayScreen(),
        );
      },
    );
  }
}
