import 'package:flutter_test/flutter_test.dart';

import 'package:ginlo/main.dart';

void main() {
  testWidgets('tabs switch between Home, Bill and Catalog', (tester) async {
    await tester.pumpWidget(const GinLoApp());
    expect(find.text("Today's earnings will show here"), findsOneWidget);

    await tester.tap(find.text('Bill'));
    await tester.pump(); // no camera in tests, so don't wait for it to settle
    expect(find.textContaining('New bill'), findsOneWidget);

    await tester.tap(find.text('Catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Your products will show here'), findsOneWidget);
  });
}
