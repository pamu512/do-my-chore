import 'package:flutter/material.dart';

import 'core/demo_auth.dart';
import 'core/dmc_theme.dart';
import 'core/supabase_config.dart';
import 'features/shell/role_switch_shell.dart';

class DoMyChoreApp extends StatefulWidget {
  const DoMyChoreApp({super.key});

  @override
  State<DoMyChoreApp> createState() => _DoMyChoreAppState();
}

class _DoMyChoreAppState extends State<DoMyChoreApp> {
  late final Future<RoleClients?> _connect;

  @override
  void initState() {
    super.initState();
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
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not reach Supabase.\n\n'
                    'Start it with `supabase start` in the repo root, then run the app with '
                    '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...\n\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return RoleSwitchShell(clients: snap.data);
        },
      ),
    );
  }
}
