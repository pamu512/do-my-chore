import 'package:flutter/material.dart';

import 'core/demo_auth.dart';
import 'core/dmc_theme.dart';
import 'core/supabase_config.dart';
import 'features/shell/role_switch_shell.dart';
import 'widgets/brand_logo.dart';

class DoMyChoreApp extends StatefulWidget {
  const DoMyChoreApp({super.key, this.connect});

  /// Injected auth future for widget tests. Production reads env in [initState].
  final Future<RoleClients?>? connect;

  @override
  State<DoMyChoreApp> createState() => _DoMyChoreAppState();
}

class _DoMyChoreAppState extends State<DoMyChoreApp> {
  late final Future<RoleClients?> _connect;

  @override
  void initState() {
    super.initState();
    if (widget.connect != null) {
      _connect = widget.connect!;
      return;
    }
    final config = SupabaseConfig.fromEnvironment();
    _connect = config == null
        ? Future.value(null)
        : DemoAuth.connect(config).then((v) => v);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Do My Chore',
      theme: Dmc.theme(false),
      home: FutureBuilder<RoleClients?>(
        future: _connect,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const BrandSplash();
          }
          if (snap.hasError) {
            return BrandSplash(
              showProgress: false,
              message:
                  'Could not reach Supabase.\n\n'
                  'Start it with `supabase start` in the repo root, then run the app with '
                  '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...\n\n${snap.error}',
            );
          }
          return RoleSwitchShell(clients: snap.data);
        },
      ),
    );
  }
}
