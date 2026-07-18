import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:share_list/app.dart';

void main() {
  testWidgets('Share List mode picker renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ShareListApp(),
      ),
    );

    expect(find.text('Share List'), findsOneWidget);
    expect(find.text('Host Mode'), findsOneWidget);
    expect(find.text('Connect Mode'), findsOneWidget);
  });
}
