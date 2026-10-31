import 'package:flutter_test/flutter_test.dart';

import 'package:ginlo/main.dart';

void main() {
  testWidgets('opens on Bill and shows every tab', (tester) async {
    await tester.pumpWidget(const GinLoApp());
    await tester.pump(); // no camera or database in tests, so don't wait for them to settle
    expect(find.text('New bill'), findsOneWidget);
    for (final tab in ['Bill', 'Home', 'Catalog', 'Learn', 'Lab']) {
      expect(find.text(tab), findsWidgets); // tests run as the dev flavor, so Lab is there
    }

    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(find.text("Today's earnings will show here"), findsOneWidget);
  });
}
