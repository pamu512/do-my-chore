import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:do_my_chore/core/demo_auth.dart';
import 'package:do_my_chore/features/parent/approvals_screen.dart';
import 'package:do_my_chore/services/chore_service.dart';

void main() {
  testWidgets('pendingForParent runs on the first frame', (tester) async {
    const authOptions = AuthClientOptions(autoRefreshToken: false);
    final parent = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: authOptions,
    );
    final kid = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: authOptions,
    );

    var calls = 0;
    final service = ChoreService(
      RoleClients(parent: parent, kid: kid),
      pendingForParentOverride: () async {
        calls += 1;
        return <Object>[];
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: ApprovalsScreen(service: service),
    ));

    expect(calls, 1);

    await tester.pump();
    expect(calls, 1);
    expect(find.text('Nothing waiting.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
