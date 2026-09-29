import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/app.dart';
import 'package:do_my_chore/core/demo_auth.dart';
import 'package:do_my_chore/widgets/brand_logo.dart';

void main() {
  testWidgets('auth entry splash shows official brand logo', (tester) async {
    final pending = Completer<RoleClients?>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(null);
    });

    await tester.pumpWidget(DoMyChoreApp(connect: pending.future));
    await tester.pump();

    expect(find.byKey(const Key('dmc-brand-logo')), findsOneWidget);
    final image = tester.widget<Image>(find.byKey(const Key('dmc-brand-logo')));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, BrandAssets.logo);
  });

  testWidgets('auth error screen keeps the official brand logo', (tester) async {
    await tester.pumpWidget(
      DoMyChoreApp(
        connect: Future<RoleClients?>.delayed(
          Duration.zero,
          () => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dmc-brand-logo')), findsOneWidget);
    expect(find.textContaining('Could not reach Supabase'), findsOneWidget);
  });
}
