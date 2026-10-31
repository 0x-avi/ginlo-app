import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ginlo/main.dart';

/// Pretend the test screen is a phone held a given way (the default test screen is 800x600).
void _phone(WidgetTester tester, {required bool landscape}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = landscape ? const Size(2400, 1080) : const Size(1080, 2400);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('portrait: opens on Bill, tab bar at the bottom', (tester) async {
    _phone(tester, landscape: false);
    await tester.pumpWidget(const GinLoApp());
    await tester.pump(); // no camera or database in tests, so don't wait for them to settle
    expect(find.text('Add to bill'), findsOneWidget); // Bill screen is first
    expect(find.byType(BottomAppBar), findsOneWidget);
    for (final tab in ['Bill', 'Home', 'Products', 'Learn', 'Modify', 'Lab']) {
      expect(find.text(tab), findsWidgets); // tests run as the dev flavor, so Lab is there
    }

    await tester.tap(find.text('Home'));
    await tester.pump();
    // No database in tests, so the dashboard itself can't load; check the Ginlo header is there.
    expect(find.byWidgetPredicate((w) => w is Image && '${w.image}'.contains('ginlo_logo')), findsWidgets);
  });

  testWidgets('landscape: tabs on a side rail, no title bar over the camera', (tester) async {
    _phone(tester, landscape: true);
    await tester.pumpWidget(const GinLoApp());
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('New bill'), findsNothing);
  });
}
