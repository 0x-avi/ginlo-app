import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ginlo/main.dart';

/// Pretend the test screen is a portrait phone (the default test screen is 800x600).
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opens on Bill, tab bar at the bottom', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const GinLoApp());
    await tester.pump(); // no camera or database in tests, so don't wait for them to settle
    expect(find.text('New bill'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final tab in ['Bill', 'Home', 'Catalog', 'Learn', 'Lab']) {
      expect(find.text(tab), findsWidgets); // tests run as the dev flavor, so Lab is there
    }

    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(find.text("Today's earnings will show here"), findsOneWidget);
  });
}
