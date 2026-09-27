import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/app.dart';

void main() {
  testWidgets('app boots to Parent Home without backend config', (tester) async {
    await tester.pumpWidget(const DoMyChoreApp());
    await tester.pumpAndSettle();
    expect(find.text('Do My Chore'), findsOneWidget);
    expect(find.text('Parent Home'), findsOneWidget);
  });
}
