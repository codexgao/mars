// Basic smoke test for the xlog_flutter example app.

import 'package:flutter_test/flutter_test.dart';

import 'package:xlog_flutter_example/main.dart';

void main() {
  testWidgets('xlog_flutter demo smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // App bar title should be visible
    expect(find.text('xlog_flutter Demo'), findsOneWidget);

    // All control buttons should be present
    expect(find.text('Open XLog'), findsOneWidget);
    expect(find.text('Write Logs'), findsOneWidget);
    expect(find.text('Flush Sync'), findsOneWidget);
    expect(find.text('Close XLog'), findsOneWidget);

    // Initial status text should be shown
    expect(find.text('Not initialized'), findsOneWidget);
  });
}
