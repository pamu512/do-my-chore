import 'package:flutter/material.dart';

import '../../core/demo_auth.dart';
import '../../core/dmc_theme.dart';
import '../../models/role.dart';
import '../../services/album_service.dart';
import '../../services/chore_service.dart';
import '../../services/goal_service.dart';
import '../kid/today_screen.dart';
import '../parent/home_screen.dart';
import 'role_scope.dart';

/// App shell with the in-app Parent <-> Kid role switch. Two pre-authenticated
/// clients mean switching never re-authenticates - the demo video depends on
/// it - and every call runs under the active role's JWT so RLS always applies.
///
/// Chrome mirrors the C-Ledger mock: brand wordmark, a pill role switch whose
/// thumb slides between pine (parent) and marigold (kid), and the honesty
/// line under it. The whole theme swaps accent with the role.
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
        final isKid = role == Role.kid;
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

        return Theme(
          data: Dmc.theme(isKid),
          child: Scaffold(
            backgroundColor: Dmc.bg,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        Text('Do My Chore', style: Dmc.displayStyle(size: 17.5, weight: FontWeight.w700)),
                        const Spacer(),
                        _RolePill(role: role, onSelect: (r) => scope.role = r),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                    child: Text(
                      'Demo ledger - real money settles offline.',
                      style: TextStyle(
                        fontFamily: Dmc.text,
                        fontSize: 12,
                        color: Dmc.faint,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Container(height: 1, color: Dmc.line),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The mock's `.rt` pill: white track, sliding accent thumb, Parent | Kid.
class _RolePill extends StatelessWidget {
  const _RolePill({required this.role, required this.onSelect});

  final Role role;
  final ValueChanged<Role> onSelect;

  @override
  Widget build(BuildContext context) {
    final kidActive = role == Role.kid;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Dmc.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Dmc.lineStrong),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: kidActive ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 76,
              height: 38,
              decoration: BoxDecoration(
                color: kidActive ? Dmc.marigold : Dmc.pine,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pillButton(
                label: 'Parent',
                selected: !kidActive,
                onTap: () => onSelect(Role.parent),
              ),
              _pillButton(
                label: 'Kid',
                selected: kidActive,
                onTap: () => onSelect(Role.kid),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 76,
        height: 38,
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontFamily: Dmc.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? (role == Role.kid ? Dmc.ink : Colors.white) : Dmc.ink2,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
