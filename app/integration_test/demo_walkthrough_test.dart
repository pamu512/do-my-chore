import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:do_my_chore/app.dart';

Future<void> _shot(IntegrationTestWidgetsFlutterBinding binding, String name) async {
  await binding.convertFlutterSurfaceToImage();
  await binding.takeScreenshot(name);
}

Future<void> _settle(WidgetTester tester, [int ms = 800]) async {
  await tester.pumpAndSettle(Duration(milliseconds: ms));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo walkthrough beats 1-10', (tester) async {
    await tester.pumpWidget(const DoMyChoreApp());
    // Wait for Supabase demo auth + first frame
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Parent Home').evaluate().isNotEmpty ||
          find.text('Kid Today').evaluate().isNotEmpty) {
        break;
      }
    }
    await _settle(tester, 1500);

    // Ensure Parent
    if (find.text('Kid Today').evaluate().isNotEmpty) {
      await tester.tap(find.text('Parent'));
      await _settle(tester);
    }

    // ---- Beat 1: Parent Home ----
    expect(find.textContaining('Disneyland'), findsWidgets);
    expect(find.textContaining('\$3500'), findsWidgets);
    expect(find.textContaining('real money settles offline'), findsOneWidget);
    await _shot(binding, 'beat-01');

    // ---- Beat 2: New Goal → Suggest plan ----
    await tester.tap(find.text('New Goal'));
    await _settle(tester);
    expect(find.text('New Goal'), findsWidgets);

    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.at(0), 'Camping trip');
    await tester.enterText(fields.at(1), '300');
    await tester.pump();
    await tester.tap(find.text('Suggest plan'));
    await _settle(tester, 2000);
    expect(find.text('WHY THIS PLAN'), findsOneWidget);
    expect(find.textContaining('Weekly top-up'), findsOneWidget);
    await _shot(binding, 'beat-02');

    // ---- Beat 3: Accept plan ----
    // The plan card is tall; scroll the (lazy) ListView until the CTA builds.
    // An explicit scroller: TextFields carry their own Scrollables.
    await tester.scrollUntilVisible(
      find.text('Accept plan'),
      200,
      scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      maxScrolls: 24,
    );
    await tester.tap(find.text('Accept plan'));
    await _settle(tester, 2000);
    if (find.textContaining('WHAT WILL THIS REALLY COST').evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('Keep my'));
      await _settle(tester, 1500);
    }
    expect(find.textContaining('Camping trip'), findsWidgets);
    await _shot(binding, 'beat-03');
    // Keep beats 4-8 deterministic on the seeded Disneyland goal: archive the
    // goal the walkthrough just created via REST (same pattern as album seed).
    await _archiveGoalByTitle('Camping trip');

    // ---- Beat 4: Role switch to Kid ----
    await tester.tap(find.text('Kid'));
    await _settle(tester);
    expect(find.text('Kid Today'), findsOneWidget);
    await _shot(binding, 'beat-04');

    // ---- Beat 5: Open photo chore, take photo, submit ----
    // Seeded Disneyland photo chore (rev 3 seed)
    final photoChore = find.text('Make your bed');
    expect(photoChore, findsOneWidget);
    await tester.tap(photoChore);
    await _settle(tester);
    expect(find.text('Take a photo'), findsOneWidget);
    await tester.tap(find.text('Take a photo'));
    await _settle(tester);
    expect(find.textContaining('Photo attached'), findsOneWidget);
    await _shot(binding, 'beat-05');
    await tester.tap(find.text('Done! Send to parent'));
    await _settle(tester, 2500);
    if (find.text('Back to today').evaluate().isNotEmpty) {
      await tester.tap(find.text('Back to today'));
      await _settle(tester);
    }

    // ---- Beat 6: Parent Approvals → approve ----
    await tester.tap(find.text('Parent'));
    await _settle(tester);
    // Pending card
    final pending = find.textContaining('waiting for approval');
    expect(pending, findsOneWidget);
    await tester.tap(pending);
    await _settle(tester, 1500);
    // Approve first pending (labeled button)
    final approve = find.text('Approve');
    expect(approve, findsWidgets);
    await tester.tap(approve.first);
    await _settle(tester, 2000);
    await _shot(binding, 'beat-06');

    // Pop back to Parent Home if still on approvals
    if (find.text('Approve').evaluate().isNotEmpty ||
        find.textContaining('Nothing waiting').evaluate().isNotEmpty) {
      await _popPage(tester);
    }

    // ---- Beat 7: Progress moved (kid bar) ----
    await tester.tap(find.text('Kid'));
    await _settle(tester, 1500);
    // Goal bank should have moved (\$4 of \$5 at 80%)
    expect(find.textContaining('Disneyland'), findsWidgets);
    await _shot(binding, 'beat-07');

    // Submit another photo chore for reject path
    final dishes = find.text('Wash the dishes');
    expect(dishes, findsOneWidget);
    await tester.tap(dishes);
    await _settle(tester);
    await tester.tap(find.text('Take a photo'));
    await _settle(tester);
    await tester.tap(find.text('Done! Send to parent'));
    await _settle(tester, 2500);
    if (find.text('Back to today').evaluate().isNotEmpty) {
      await tester.tap(find.text('Back to today'));
      await _settle(tester);
    }

    // ---- Beat 8: Send back → next try ----
    await tester.tap(find.text('Parent'));
    await _settle(tester);
    await tester.tap(find.textContaining('waiting for approval'));
    await _settle(tester, 1500);
    final reject = find.text('Send back');
    expect(reject, findsWidgets);
    await tester.tap(reject.first);
    await _settle(tester, 800);
    await tester.tap(find.text('Send note'));
    await _settle(tester, 1500);
    if (find.byType(BackButton).evaluate().isNotEmpty || find.byIcon(Icons.arrow_back).evaluate().isNotEmpty) {
      await tester.pageBack();
      await _settle(tester);
    } else {
      // Nested scaffolds: try Navigator pop via back gesture substitute
      final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
      nav.pop();
      await _settle(tester);
    }
    await tester.tap(find.text('Kid'));
    await _settle(tester, 1500);
    expect(find.text('NEXT TRY'), findsWidgets);
    expect(find.textContaining('Try again'), findsNothing);
    await _shot(binding, 'beat-08');

    // ---- Beat 9: Goal Album ----
    await tester.tap(find.text('Parent'));
    await _settle(tester);
    // Beat 6's approve filed the bed photo into the album (approve path
    // wires AlbumService.addToAlbum; no REST seeding anymore).
    await tester.tap(find.text('Goal Album').first);
    await _settle(tester, 1500);
    expect(find.text('Goal Album'), findsWidgets);
    expect(find.text('Make your bed'), findsWidgets);
    // Delete if present
    final del = find.byTooltip('Delete from album');
    if (del.evaluate().isNotEmpty) {
      await tester.tap(del.first);
      await _settle(tester);
    }
    await _shot(binding, 'beat-09');

    // ---- Beat 10: Honesty banners ----
    await _popPage(tester);
    await _settle(tester);
    expect(find.textContaining('real money settles offline'), findsOneWidget);
    expect(find.textContaining('test data only'), findsOneWidget);
    await _shot(binding, 'beat-10');
  });
}

/// Pop the current page off the root navigator (pageBack's finder is
/// platform-fragile under integration bindings).
Future<void> _popPage(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
  nav.pop();
  await tester.pumpAndSettle(const Duration(milliseconds: 800));
}

/// Archive a goal by title via REST as parent (keeps beats 4-8 on Disneyland).
Future<void> _archiveGoalByTitle(String title) async {
  const url = String.fromEnvironment('SUPABASE_URL');
  const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || anon.isEmpty) return;

  final login = await HttpClient()
      .postUrl(Uri.parse('$url/auth/v1/token?grant_type=password'));
  login.headers.set('apikey', anon);
  login.headers.set('Content-Type', 'application/json');
  login.add(utf8.encode(jsonEncode({'email': 'parent@demo', 'password': 'demo1234'})));
  final loginRes = await login.close();
  final loginBody = jsonDecode(await loginRes.transform(utf8.decoder).join()) as Map;
  final token = loginBody['access_token'] as String;

  final req = await HttpClient()
      .openUrl('PATCH', Uri.parse('$url/rest/v1/goals?title=eq.$title'));
  req.headers.set('apikey', anon);
  req.headers.set('Authorization', 'Bearer $token');
  req.headers.set('Content-Type', 'application/json');
  req.headers.set('Prefer', 'return=minimal');
  req.add(utf8.encode(jsonEncode({'status': 'archived'})));
  await req.close();
}

